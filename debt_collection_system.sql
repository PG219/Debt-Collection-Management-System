DROP DATABASE IF EXISTS debt_collection_db;
CREATE DATABASE debt_collection_db;
USE debt_collection_db;

CREATE TABLE Agency (Agency_ID INT AUTO_INCREMENT PRIMARY KEY, Agency_Name VARCHAR(100) NOT NULL, Contact_Number VARCHAR(20), Commission_Rate DECIMAL(5,2) NOT NULL CHECK (Commission_Rate BETWEEN 0 AND 100));

CREATE TABLE Customer (Customer_ID INT AUTO_INCREMENT PRIMARY KEY, Email VARCHAR(150) NOT NULL UNIQUE, Phone_Number VARCHAR(20), Risk_Level ENUM('Low','Medium','High') DEFAULT 'Medium', Registration_Date DATETIME DEFAULT CURRENT_TIMESTAMP);

CREATE TABLE Individual_Customer (Customer_ID INT PRIMARY KEY, First_Name VARCHAR(50) NOT NULL, Last_Name VARCHAR(50) NOT NULL, National_ID VARCHAR(50) UNIQUE, CONSTRAINT fk_individual_customer FOREIGN KEY (Customer_ID) REFERENCES Customer(Customer_ID) ON DELETE CASCADE);

CREATE TABLE Corporate_Customer (Customer_ID INT PRIMARY KEY, Company_Name VARCHAR(150) NOT NULL, Tax_Reg_Number VARCHAR(50) UNIQUE, Contact_Person VARCHAR(100), CONSTRAINT fk_corporate_customer FOREIGN KEY (Customer_ID) REFERENCES Customer(Customer_ID) ON DELETE CASCADE);

CREATE TABLE Invoice (Invoice_ID INT AUTO_INCREMENT PRIMARY KEY, Amount_Due DECIMAL(12,2) NOT NULL CHECK (Amount_Due > 0), Due_Date DATE NOT NULL, Status ENUM('Open','Settled','Uncollectible','Legal Action Required','Closed') DEFAULT 'Open', Customer_ID INT NOT NULL, Agency_ID INT, CONSTRAINT fk_invoice_customer FOREIGN KEY (Customer_ID) REFERENCES Customer(Customer_ID), CONSTRAINT fk_invoice_agency FOREIGN KEY (Agency_ID) REFERENCES Agency(Agency_ID) ON DELETE SET NULL);

CREATE TABLE Payment (Payment_ID INT AUTO_INCREMENT PRIMARY KEY, Payment_Date DATETIME DEFAULT CURRENT_TIMESTAMP, Amount_Paid DECIMAL(12,2) NOT NULL CHECK (Amount_Paid > 0), Payment_Method VARCHAR(50), Invoice_ID INT NOT NULL, Commission_Amount DECIMAL(12,2) AS (Amount_Paid * (SELECT Commission_Rate / 100 FROM Agency a JOIN Invoice i ON i.Agency_ID = a.Agency_ID WHERE i.Invoice_ID = Payment.Invoice_ID LIMIT 1)) STORED, CONSTRAINT fk_payment_invoice FOREIGN KEY (Invoice_ID) REFERENCES Invoice(Invoice_ID) ON DELETE CASCADE);

DELIMITER $$

CREATE TRIGGER trg_auto_close_invoice
AFTER INSERT ON Payment
FOR EACH ROW
BEGIN
DECLARE total_paid DECIMAL(12,2);
DECLARE amount_due DECIMAL(12,2);
SELECT SUM(Amount_Paid) INTO total_paid FROM Payment WHERE Invoice_ID = NEW.Invoice_ID;
SELECT Amount_Due INTO amount_due FROM Invoice WHERE Invoice_ID = NEW.Invoice_ID;
IF total_paid >= amount_due THEN
UPDATE Invoice SET Status = 'Closed' WHERE Invoice_ID = NEW.Invoice_ID;
END IF;
END$$

CREATE TRIGGER trg_block_payment_on_closed
BEFORE INSERT ON Payment
FOR EACH ROW
BEGIN
DECLARE inv_status VARCHAR(30);
SELECT Status INTO inv_status FROM Invoice WHERE Invoice_ID = NEW.Invoice_ID;
IF inv_status = 'Closed' THEN
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: Cannot add payment. Invoice is already Closed.';
END IF;
END$$

CREATE TRIGGER trg_legal_escalation
BEFORE UPDATE ON Invoice
FOR EACH ROW
BEGIN
IF NEW.Status = 'Open' AND DATEDIFF(CURDATE(), OLD.Due_Date) > 90 THEN
SET NEW.Status = 'Legal Action Required';
END IF;
END$$

DELIMITER ;

CREATE VIEW AgencyPerformanceView AS
SELECT a.Agency_ID, a.Agency_Name, a.Commission_Rate,
COUNT(DISTINCT i.Invoice_ID) AS Total_Invoices_Assigned,
SUM(p.Amount_Paid) AS Total_Amount_Recovered,
SUM(p.Commission_Amount) AS Total_Commission_Earned,
ROUND((COUNT(DISTINCT CASE WHEN i.Status='Closed' THEN i.Invoice_ID END) / COUNT(DISTINCT i.Invoice_ID))*100,2) AS Recovery_Rate_Percent
FROM Agency a
LEFT JOIN Invoice i ON a.Agency_ID=i.Agency_ID
LEFT JOIN Payment p ON i.Invoice_ID=p.Invoice_ID
GROUP BY a.Agency_ID,a.Agency_Name,a.Commission_Rate;

CREATE VIEW OverdueInvoicesView AS
SELECT i.Invoice_ID,i.Amount_Due,i.Due_Date,DATEDIFF(CURDATE(),i.Due_Date) AS Days_Overdue,i.Status,c.Email AS Debtor_Email,c.Phone_Number AS Debtor_Phone,a.Agency_Name AS Assigned_Agency
FROM Invoice i
JOIN Customer c ON i.Customer_ID=c.Customer_ID
LEFT JOIN Agency a ON i.Agency_ID=a.Agency_ID
WHERE i.Due_Date<CURDATE() AND i.Status NOT IN ('Closed','Settled');

CREATE VIEW InvoicePaymentSummary AS
SELECT i.Invoice_ID,i.Amount_Due,i.Status,
COALESCE(SUM(p.Amount_Paid),0) AS Total_Paid,
i.Amount_Due-COALESCE(SUM(p.Amount_Paid),0) AS Remaining_Balance,
COUNT(p.Payment_ID) AS Payment_Count
FROM Invoice i
LEFT JOIN Payment p ON i.Invoice_ID=p.Invoice_ID
GROUP BY i.Invoice_ID,i.Amount_Due,i.Status;

DELIMITER $$

CREATE PROCEDURE AssignInvoiceToAgency(IN p_invoice_id INT, IN p_agency_id INT)
BEGIN
DECLARE current_agency INT;
SELECT Agency_ID INTO current_agency FROM Invoice WHERE Invoice_ID=p_invoice_id;
IF current_agency IS NOT NULL THEN
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='ERROR: Invoice is already assigned to an agency.';
ELSE
UPDATE Invoice SET Agency_ID=p_agency_id WHERE Invoice_ID=p_invoice_id;
SELECT 'Invoice successfully assigned.' AS Result;
END IF;
END$$

CREATE PROCEDURE RecordPayment(IN p_invoice_id INT, IN p_amount_paid DECIMAL(12,2), IN p_method VARCHAR(50))
BEGIN
INSERT INTO Payment (Invoice_ID,Amount_Paid,Payment_Method) VALUES (p_invoice_id,p_amount_paid,p_method);
SELECT 'Payment recorded successfully.' AS Result;
END$$

DELIMITER ;

INSERT INTO Agency (Agency_Name,Contact_Number,Commission_Rate) VALUES
('Swift Recovery Ltd.','9876543210',12.00),
('ClearDebt Solutions','9123456780',10.50),
('Alpha Collections Inc.','9988776655',15.00);

INSERT INTO Customer (Email,Phone_Number,Risk_Level) VALUES
('rahul.mehta@email.com','9001122334','High'),
('priya.singh@email.com','9002233445','Medium'),
('techcorp@business.com','9003344556','Low'),
('globalfinance@corp.com','9004455667','High'),
('amit.kumar@personal.com','9005566778','Medium');

INSERT INTO Individual_Customer (Customer_ID,First_Name,Last_Name,National_ID) VALUES
(1,'Rahul','Mehta','IND-2024-001'),
(2,'Priya','Singh','IND-2024-002'),
(5,'Amit','Kumar','IND-2024-005');

INSERT INTO Corporate_Customer (Customer_ID,Company_Name,Tax_Reg_Number,Contact_Person) VALUES
(3,'TechCorp Pvt. Ltd.','TXREG-TC-001','Rohan Joshi'),
(4,'Global Finance Corp.','TXREG-GF-002','Sneha Patel');

INSERT INTO Invoice (Amount_Due,Due_Date,Status,Customer_ID,Agency_ID) VALUES
(50000.00,'2024-10-01','Open',1,1),
(12000.00,'2024-09-15','Open',2,2),
(200000.00,'2024-08-01','Legal Action Required',3,3),
(75000.00,'2024-11-20','Open',4,1),
(9500.00,'2024-12-01','Open',5,NULL),
(30000.00,'2024-07-10','Closed',1,2);

INSERT INTO Payment (Invoice_ID,Amount_Paid,Payment_Method) VALUES
(1,20000.00,'Bank Transfer'),
(1,15000.00,'UPI'),
(2,12000.00,'Cheque'),
(3,50000.00,'Bank Transfer'),
(6,30000.00,'Online Banking');

SELECT * FROM OverdueInvoicesView;
SELECT * FROM InvoicePaymentSummary;
SELECT * FROM AgencyPerformanceView;

SELECT ic.First_Name,ic.Last_Name,ic.National_ID,c.Email,c.Phone_Number,c.Risk_Level
FROM Individual_Customer ic
JOIN Customer c ON ic.Customer_ID=c.Customer_ID
WHERE c.Risk_Level='High';

SELECT Invoice_ID,Amount_Due,Due_Date,DATEDIFF(CURDATE(),Due_Date) AS Days_Overdue,Status
FROM Invoice
WHERE Status='Open' AND DATEDIFF(CURDATE(),Due_Date)>90;

SELECT a.Agency_Name,SUM(p.Commission_Amount) AS Total_Commission
FROM Payment p
JOIN Invoice i ON p.Invoice_ID=i.Invoice_ID
JOIN Agency a ON i.Agency_ID=a.Agency_ID
GROUP BY a.Agency_Name;

CALL AssignInvoiceToAgency(5,3);
CALL RecordPayment(1,10000.00,'UPI');
