USE SolarEdge;
CREATE TABLE dbo.ProductionHistory
(
    date SMALLDATETIME NOT NULL PRIMARY KEY,
    kWh decimal(10,2)
);

CREATE TABLE dbo.ConsumptionHistory
(
    date SMALLDATETIME NOT NULL PRIMARY KEY,
    kWh decimal(10,2)
);


CREATE TABLE dbo.PurchaseHistory
(
    date SMALLDATETIME NOT NULL PRIMARY KEY,
    kWh DECIMAL(10,2),
    isWeekend BIT,
    tarrif VARCHAR(50),
    rate VARCHAR(50)
);

CREATE TABLE dbo.RateCard
(
    tarrif VARCHAR(50) NOT NULL PRIMARY KEY,
    rate DECIMAL (10,4) NOT NULL
);

CREATE TABLE dbo.Tarrif
(
    hour TIME NOT NULL,
    isWeekend BIT NOT NULL,
    tarrif VARCHAR(50),
    --FOREIGN KEY (tarrif) REFERENCES RateCard(tarrif)
)

CREATE TABLE dbo.ProductionBaseline
(
    date DATE NOT NULL PRIMARY KEY,
    kWh decimal(10,2)
);
