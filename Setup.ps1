#requires -Modules SqlServer

# Define global variables
[DateTime]$InstallationDate = Get-Date '01/09/2017'
$parameters = Get-Content .\parameters.json | ConvertFrom-Json
$ConnectionString = "Server=$($parameters.sqlServerName); Database=SolarEdge; User Id=$($parameters.sqlUsername); Password=$($parameters.sqlPassword)"

# Import the module
Import-Module .\modules\SolarEdge.psm1


# Create the Datbase
Invoke-Sqlcmd -Query "CREATE DATABASE SolarEdge" -Username $parameters.sqlUsername -Password $parameters.sqlPassword -ServerInstance $parameters.sqlServerName  -Verbose 
Invoke-Sqlcmd -InputFile .\SQL\Create-Tables.sql -ConnectionString $ConnectionString -Verbose

# Seed reference tables
Invoke-Sqlcmd -InputFile .\SQL\Seed-Tables.sql -ConnectionString $ConnectionString -Verbose

# Populate the database with historical data
Get-EnergyDetailHistory -StartDate (Get-Date '01/09/2017') | Export-EnergyDetailHistory -Verbose

