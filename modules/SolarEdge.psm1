#Requires -Modules SqlServer

# Reference:
# https://www.solaredge.com/sites/default/files/se_monitoring_api.pdf

# Define globals
[DateTime]$InstallationDate = Get-date (Get-AutomationVariable -Name 'SolarEdgeInstallationDate')
$ConnectionString = Get-AutomationVariable -Name 'SqlConnectionString'
$SiteID = Get-AutomationVariable -Name 'SolarEdgeSiteID'
$APIKey = Get-AutomationVariable -Name 'SolarEdgeAPIKey'

#[DateTime]$InstallationDate = Get-Date '01/09/2017'
#$parameters = Get-Content .\parameters.json | ConvertFrom-Json
#$ConnectionString = "Server=$($parameters.sqlServerName); Database=SolarEdge; User Id=$($parameters.sqlUsername); Password=$($parameters.sqlPassword)"


Class MeterReading {
    [ValidateSet("Production", "Consumption", "Purchased")]
    [String]$Type

    [DateTime]$Date

    [int]$Wh

    MeterReading([String]$Type, [DateTime]$Date, [int]$Wh) {
        $this.Type = $Type
        $this.Date = $Date
        $this.Wh = $Wh
    }
}

Function Get-EnergyDetailHistory {
    # Getting the ganular energy details on a per-month bassis.
    param (
        [Parameter(Mandatory = $True)]
        [DateTime]$StartDate,
        [DateTime]$EndDate = [DateTime]::Today.AddSeconds(-1) # Default: Midnight Yesterday 
    )

    # If the end date is in a different year - exit.
    If ($StartDate.Year -ne $EndDate.Year) {
        Throw "Start Date and End Date cannot span multiple years."
    }
    
    # If the end date is in the future
    # Get everything up to yesterday
    If ($EndDate -gt (Get-Date)) {
        $EndDate = [DateTime]::Today.AddSeconds(-1) # Midnight Yesterday
    }

    # API only supports max of 1 month results for this level of granularity
    # Loop through each month
    $output = @()

    $baseUrl = "/site/$($SiteID)/energyDetails"

    # If the start date and end date are in the same month
    # Use exact values
    if ($EndDate.Month -eq $StartDate.Month) {
        $reqUrl = "https://monitoringapi.solaredge.com" + $baseUrl + "?timeUnit=QUARTER_OF_AN_HOUR&meters=PRODUCTION,CONSUMPTION,PURCHASED&startTime=$(($StartDate).ToString('yyyy-MM-dd'))%2000:00:00&endTime=$(($EndDate).ToString('yyyy-MM-dd'))%2023:59:59&api_key=$($APIKey)"

        $results = (Invoke-RestMethod -Method GET -Uri $reqUrl).energyDetails.meters
        foreach ($type in $results) {
            foreach ($reading in $type.values) {
                $output += [MeterReading]::New($type.type, $reading.date, $reading.value)
            }
        }
    }
    else {
        # if the start date and end date are in different months, then set
        # begin from the first of every month
        for ([int]$i = $StartDate.Month; $i -le $EndDate.Month; $i++) {
            [DateTime]$Start = Get-Date "01/$i/$($StartDate.Year)"
            [DateTIme]$End = $Start.AddMonths(1).AddSeconds(-1) # Set to last day of the month

            If ($End -gt (Get-Date)) {
                $End = [DateTime]::Today.AddSeconds(-1) # Midnight Yesterday
            }

            $reqUrl = "https://monitoringapi.solaredge.com" + $baseUrl + "?timeUnit=QUARTER_OF_AN_HOUR&meters=PRODUCTION,CONSUMPTION,PURCHASED&startTime=$(($Start).ToString('yyyy-MM-dd'))%2000:00:00&endTime=$(($End).ToString('yyyy-MM-dd'))%2023:59:59&api_key=$($APIKey)"

            $results = (Invoke-RestMethod -Method GET -Uri $reqUrl).energyDetails.meters
            foreach ($type in $results) {
                foreach ($reading in $type.values) {
                    $output += [MeterReading]::New($type.type, $reading.date, $reading.value)
                }
            }
        }
    }
    return $output
}

Function Get-SiteEnergyTotalCostByMonth {
    [cmdletbinding()]
    param(
        [DateTime]$StartDate
    )
    
    [decimal]$TotalCost = 0.00
    $HolidayUri = 'https://data.gov.au/api/3/action/datastore_search?resource_id=31eec35e-1de6-4f04-9703-9be1d43d405b'

    # Get the purchase data for the date period
    $query = @"
    DECLARE @sp_Date DATETIME
    SET @sp_Date = '$(($StartDate).ToString('yyyy-MM-dd'))'

    SELECT * FROM PurchaseHistory 
    WHERE date >= @sp_Date
    AND date < DateAdd(m, 1, @sp_Date);
"@

    $PurchaseData = Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $query
    
    # Get the rate card & tarrif information
    $query = @"
        SELECT tarrif.hour, tarrif.tarrif, tarrif.weekend, RateCard.Rate 
        FROM tarrif
        INNER JOIN RateCard ON tarrif.tarrif = ratecard.tarrif
"@
    $TarrifData = Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $query

    # Get the public holidays for NSW
    $Holidays = (Invoke-RestMethod -Uri $holidayUri -Method GET).result.records | Where-Object 'Applicable To' -in ('NSW', 'NAT')

    # Loop through each day in the month returned    
    ForEach ($Hour in $PurchaseData) {
        [bool]$isWeekend = $false

        #Determine if the date is a weekend or not
        If (($Hour.date.DayOfWeek -eq 'Saturday') -or ($Hour.date.DayOfWeek -eq 'Sunday') ) {
            $isWeekend = $true
        } 
        # Determine if the date is a public holiday
        If ($hour.date.Tostring('yyyyMMdd') -in $holidays.Date ) {
            $isWeekend = $True  
        }

        # Calculate the Cost
        $rate = $TarrifData | Where-Object { ($_.hour -match $hour.date.ToString('HH:mm:ss')) -and ($_.Weekend -eq $isWeekend) }
        
        $query = "UPDATE PurchaseHistory SET isWeekend = '$isWeekend',  tarrif = '$($rate.tarrif)', rate = '$($rate.rate)' WHERE date = '$($hour.date)' "
        Write-Verbose $query
        Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $query
        $TotalCost += $rate.rate * $hour.kWh
    }
    # Add the daily supply surchage
    $query = "SELECT rate FROM RateCard WHERE tarrif = 'DailySupply'"
    [decimal]$SupplyCost = Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $query | Select-Object -ExpandProperty rate
    $TotalCost += $SupplyCost * [DateTime]::DaysInMonth($StartDate.Year, $StartDate.Month)

    return $TotalCost
}

Function Export-EnergyDetailHistory {
    # Example: 
    # Get-EnergyDetailHistory -StartDate (Get-Date '01/09/2017') | Export-EnergyDetailHistory -Truncate -Verbose
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, Mandatory = $True)]    
        [MeterReading[]]$ReadingData,
        [Switch]$Truncate
    )

    Begin {
        # Truncate the tables
        If ($truncate) {
            Write-Verbose "Truncating tables ..."
            $query = "TRUNCATE TABLE ProductionHistory"
            Invoke-Sqlcmd -Query $query -ConnectionString $ConnectionString
            $query = "TRUNCATE TABLE PurchaseHistory"
            Invoke-Sqlcmd -Query $query -ConnectionString $ConnectionString
            $query = "TRUNCATE TABLE ConsumptionHistory"
            Invoke-Sqlcmd -Query $query -ConnectionString $ConnectionString
        }
    }
    Process {
        # Loop through each meter reading passed through
        ForEach ($reading in $ReadingData) {
            switch ($reading.type) {
                'Consumption' { 
                    $query = "INSERT INTO ConsumptionHistory VALUES ('$($reading.date)', '$($reading.Wh/1000)')"
                    
                }
                'Production' {
                    $query = "INSERT INTO ProductionHistory VALUES ('$($reading.date)', '$($reading.Wh/1000)')"
                }
                'Purchased' { 
                    # PurchasedHistory table has additional fields
                    $query = "INSERT INTO PurchaseHistory (date, kWh) VALUES ('$($reading.date)', '$($reading.Wh/1000)')"
                }
            }
            
            Write-Verbose $query
            Invoke-Sqlcmd -Query $query -ConnectionString $ConnectionString
        }
    }
    End {
        Write-Verbose "Updateing PurchaseHistory rates .."
        Update-PurchaseHistoryRates
    }
}

Function Update-PurchaseHistoryRates {
    [cmdletbinding()]
    # Get the public holidays for NSW
    $HolidayUri = 'https://data.gov.au/api/3/action/datastore_search?resource_id=31eec35e-1de6-4f04-9703-9be1d43d405b'
    $Holidays = (Invoke-RestMethod -Uri $HolidayUri -Method GET).result.records | Where-Object 'Applicable To' -in ('NSW', 'NAT')

    # Get the rate card & tarrif information
    $query = @"
        SELECT tarrif.hour, tarrif.tarrif, tarrif.isWeekend, RateCard.Rate 
        FROM tarrif
        INNER JOIN RateCard ON tarrif.tarrif = ratecard.tarrif
"@
    $TarrifData = Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $query

    # Get the rows that have empty values
    $query = "SELECT date, isWeekend, tarrif, rate FROM PurchaseHistory WHERE isWeekend IS NULL AND tarrif IS NULL AND rate IS NULL"
    $results = Invoke-Sqlcmd -Query $query -ConnectionString $ConnectionString

    # Loop through each row in the results returned
    ForEach ($row in $results) {
        [bool]$isWeekend = $false

        # Determine if the date is a weekend or not
        If (($row.date.DayOfWeek -eq 'Saturday') -or ($row.date.DayOfWeek -eq 'Sunday') ) {
            $isWeekend = $true
        } 
        # Determine if the date is a public holiday
        If ($row.date.Tostring('yyyyMMdd') -in $holidays.Date ) {
            $isWeekend = $True  
        }

        # Get the rate information for the date/time
        $rate = $TarrifData | Where-Object { ($_.hour -match $row.date.ToString('HH:mm:ss')) -and ($_.isWeekend -eq $isWeekend) }
        
        # Update the table with te information
        $query = "UPDATE PurchaseHistory SET isWeekend = '$isWeekend',  tarrif = '$($rate.tarrif)', rate = '$($rate.rate)' WHERE date = '$($row.date)' "
        Write-Verbose $query
        Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $query
    }
}

Function Update-Readings {
    [cmdletbinding()]
    # Get the date of the last record in the ConsumptionHistory table
    $query = "SELECT TOP 1 CONVERT(DATE, date) as Date
                FROM ConsumptionHistory
                ORDER BY date DESC"
    $LastUpdate = Invoke-Sqlcmd -ConnectionString $ConnectionString -Query $query
    Write-Output "Last Updated: $($LastUpdate.Date)"

    # Get details and update the databse with readings
    # > LastUpdate < Today
    Get-EnergyDetailHistory -StartDate (Get-Date $LastUpdate.Date) | Export-EnergyDetailHistory -Verbose
}

#Get-EnergyDetailHistory -StartDate (Get-Date '13/12/2017') | Export-EnergyDetailHistory -Verbose

