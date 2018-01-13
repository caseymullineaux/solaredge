DECLARE @month int;
DECLARE @usageCost FLOAT;
DECLARE @supplyCharge FLOAT;

SET @month = 11;

-- Calculate the usage charges
SET @usageCost = (SELECT SUM( (kwH * rate) )
FROM PurchaseHistory
WHERE Month(date ) =  @month);

-- Daily Supply Charge
SET @supplyCharge = ( SELECT (COUNT(date)/96)*(SELECT Rate
    from RateCard
    WHERE tarrif = 'DailySupply')
FROM PurchaseHistory
WHERE MONTH(Date) = @month);

-- Add Usage cost + daily supply charge
SELECT SUM(@usageCost + @supplyCharge);
