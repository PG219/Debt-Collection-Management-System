# Design Document: Debt Collection & Recovery System (DCRS)

## Overview

The Debt Collection & Recovery System (DCRS) is a relational database application implementing Enhanced Entity-Relationship (EER) modeling with specialization hierarchies. The system provides a multi-tier architecture supporting role-based access control, automated business logic, and comprehensive audit trails.

The design emphasizes:
- **Data Integrity**: Enforcing business rules through database constraints and triggers
- **Specialization**: Using EER generalization/specialization for debtor categorization
- **Atomicity**: Ensuring transactional consistency for all payment operations
- **Security**: Encrypting PII at rest and enforcing role-based access
- **Scalability**: Supporting up to 100,000 active invoices with optimized indexing

The system consists of four primary modules:
1. Admin & Allocation Module
2. Collection Agency Module
3. Debtor Management Module
4. Legal & Compliance Module

## Architecture

### System Architecture

The DCRS follows a three-tier architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                     Presentation Layer                       │
│  (Web Interface / API for Admin, Agents, Auditors)          │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   Admin &    │  │  Collection  │  │   Legal &    │      │
│  │  Allocation  │  │    Agency    │  │  Compliance  │      │
│  │    Module    │  │    Module    │  │    Module    │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         Debtor Management Module                      │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      Data Layer                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         Relational Database (PostgreSQL/MySQL)        │  │
│  │  - User & Role Tables                                 │  │
│  │  - Debtor Tables (with Specialization)                │  │
│  │  - Invoice & Payment Tables                           │  │
│  │  - Collection Agency Tables                           │  │
│  │  - Audit Trail Tables                                 │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Database Schema Design

The database implements EER specialization using the "Class Table Inheritance" pattern:

**Debtor Specialization Hierarchy:**
```
                    ┌─────────────┐
                    │   Debtor    │
                    │  (Parent)   │
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              │                         │
        ┌─────▼──────┐          ┌──────▼──────┐
        │ Individual │          │  Corporate  │
        │   Debtor   │          │   Debtor    │
        └────────────┘          └─────────────┘
```

### Module Responsibilities

**Admin & Allocation Module:**
- User authentication and authorization
- Invoice import and validation
- Smart assignment of invoices to collection agencies
- Analytics and reporting dashboard

**Collection Agency Module:**
- Task list management for agents
- Debtor interaction logging
- Payment recording and status updates
- Commission tracking

**Debtor Management Module:**
- Debtor record creation and maintenance
- Specialization handling (Individual vs Corporate)
- Interaction history tracking
- Contact information management

**Legal & Compliance Module:**
- Legal escalation workflow
- Audit trail maintenance and querying
- Compliance reporting
- Read-only access for auditors

## Components and Interfaces

### Core Entities

#### User Entity
```
User {
  user_id: INTEGER PRIMARY KEY
  username: VARCHAR(50) UNIQUE NOT NULL
  password_hash: VARCHAR(255) NOT NULL
  role: ENUM('Administrator', 'Collection_Agent', 'Auditor') NOT NULL
  email: VARCHAR(100)
  created_at: TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  last_login: TIMESTAMP
  is_active: BOOLEAN DEFAULT TRUE
}
```

#### Debtor Entity (Parent)
```
Debtor {
  debtor_id: INTEGER PRIMARY KEY
  debtor_type: ENUM('Individual', 'Corporate') NOT NULL
  name: VARCHAR(255) NOT NULL
  contact_phone: VARCHAR(20) ENCRYPTED
  contact_email: VARCHAR(100) ENCRYPTED
  address: TEXT ENCRYPTED
  created_at: TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  updated_at: TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE
}
```

#### Individual_Debtor Entity (Specialization)
```
Individual_Debtor {
  debtor_id: INTEGER PRIMARY KEY FOREIGN KEY REFERENCES Debtor(debtor_id)
  national_id: VARCHAR(50) ENCRYPTED UNIQUE NOT NULL
  date_of_birth: DATE
  verification_status: ENUM('Pending', 'Verified', 'Failed') DEFAULT 'Pending'
  verification_date: TIMESTAMP
}
```

#### Corporate_Debtor Entity (Specialization)
```
Corporate_Debtor {
  debtor_id: INTEGER PRIMARY KEY FOREIGN KEY REFERENCES Debtor(debtor_id)
  tax_registration_number: VARCHAR(50) ENCRYPTED UNIQUE NOT NULL
  business_type: VARCHAR(100)
  registration_date: DATE
  verification_status: ENUM('Pending', 'Verified', 'Failed') DEFAULT 'Pending'
  verification_date: TIMESTAMP
}
```

#### Invoice Entity
```
Invoice {
  invoice_id: INTEGER PRIMARY KEY
  debtor_id: INTEGER NOT NULL FOREIGN KEY REFERENCES Debtor(debtor_id)
  invoice_number: VARCHAR(50) UNIQUE NOT NULL
  amount_owed: DECIMAL(15, 2) NOT NULL CHECK (amount_owed > 0)
  due_date: DATE NOT NULL
  status: ENUM('Open', 'Assigned', 'In Progress', 'Settled', 
               'Uncollectible', 'Legal Action Required', 'Closed') 
          DEFAULT 'Open'
  created_at: TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  updated_at: TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE
  assigned_agency_id: INTEGER FOREIGN KEY REFERENCES Collection_Agency(agency_id)
  assigned_agent_id: INTEGER FOREIGN KEY REFERENCES User(user_id)
  assignment_date: TIMESTAMP
}
```

#### Collection_Agency Entity
```
Collection_Agency {
  agency_id: INTEGER PRIMARY KEY
  agency_name: VARCHAR(255) NOT NULL
  contact_person: VARCHAR(255)
  contact_phone: VARCHAR(20)
  contact_email: VARCHAR(100)
  commission_rate: DECIMAL(5, 4) NOT NULL CHECK (commission_rate >= 0 AND commission_rate <= 1)
  is_active: BOOLEAN DEFAULT TRUE
  created_at: TIMESTAMP DEFAULT CURRENT_TIMESTAMP
}
```

#### Payment Entity
```
Payment {
  payment_id: INTEGER PRIMARY KEY
  invoice_id: INTEGER NOT NULL FOREIGN KEY REFERENCES Invoice(invoice_id)
  transaction_id: VARCHAR(100) UNIQUE NOT NULL
  amount_paid: DECIMAL(15, 2) NOT NULL CHECK (amount_paid > 0)
  payment_date: TIMESTAMP NOT NULL
  commission_rate: DECIMAL(5, 4) NOT NULL
  commission_amount: DECIMAL(15, 2) GENERATED ALWAYS AS (amount_paid * commission_rate) STORED
  recorded_by: INTEGER NOT NULL FOREIGN KEY REFERENCES User(user_id)
  created_at: TIMESTAMP DEFAULT CURRENT_TIMESTAMP
}
```

#### Interaction Entity
```
Interaction {
  interaction_id: INTEGER PRIMARY KEY
  debtor_id: INTEGER NOT NULL FOREIGN KEY REFERENCES Debtor(debtor_id)
  agent_id: INTEGER NOT NULL FOREIGN KEY REFERENCES User(user_id)
  invoice_id: INTEGER FOREIGN KEY REFERENCES Invoice(invoice_id)
  interaction_type: ENUM('Phone Call', 'Email', 'Letter', 
                         'In-Person Meeting', 'Legal Notice') NOT NULL
  interaction_date: TIMESTAMP NOT NULL
  outcome: VARCHAR(50)
  notes: TEXT
  created_at: TIMESTAMP DEFAULT CURRENT_TIMESTAMP
}
```

#### Audit_Trail Entity
```
Audit_Trail {
  audit_id: INTEGER PRIMARY KEY
  entity_type: VARCHAR(50) NOT NULL
  entity_id: INTEGER NOT NULL
  action: VARCHAR(50) NOT NULL
  performed_by: INTEGER NOT NULL FOREIGN KEY REFERENCES User(user_id)
  action_timestamp: TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  old_value: TEXT
  new_value: TEXT
  ip_address: VARCHAR(45)
}
```

### Key Interfaces

#### Authentication Service
```
interface AuthenticationService {
  authenticate(username: string, password: string): User | null
  authorize(user: User, operation: string, resource: string): boolean
  logSecurityEvent(user: User, event: string): void
}
```

#### Invoice Management Service
```
interface InvoiceManagementService {
  importInvoices(invoiceData: InvoiceData[]): ImportResult
  assignInvoice(invoiceId: int, agencyId: int, agentId: int): boolean
  updateInvoiceStatus(invoiceId: int, newStatus: string, userId: int): boolean
  getInvoicesByAgent(agentId: int): Invoice[]
  getInvoiceDetails(invoiceId: int): InvoiceDetails
}
```

#### Payment Processing Service
```
interface PaymentProcessingService {
  recordPayment(payment: PaymentData): PaymentResult
  calculateCommission(amountPaid: decimal, commissionRate: decimal): decimal
  getPaymentHistory(invoiceId: int): Payment[]
  getRemainingBalance(invoiceId: int): decimal
}
```

#### Debtor Management Service
```
interface DebtorManagementService {
  createIndividualDebtor(data: IndividualDebtorData): Debtor
  createCorporateDebtor(data: CorporateDebtorData): Debtor
  getDebtorDetails(debtorId: int): DebtorDetails
  getDebtorHistory(debtorId: int): InteractionHistory
  updateDebtorContact(debtorId: int, contactData: ContactData): boolean
}
```

#### Analytics Service
```
interface AnalyticsService {
  calculateRecoveryRate(filters: AnalyticsFilters): decimal
  getAgencyPerformance(agencyId: int, dateRange: DateRange): PerformanceMetrics
  generatePerformanceReport(filters: ReportFilters): Report
  getRecoveryTrends(dateRange: DateRange): TrendData
}
```

#### Encryption Service
```
interface EncryptionService {
  encrypt(plaintext: string): string
  decrypt(ciphertext: string): string
  encryptPII(piiData: PIIData): EncryptedPIIData
  decryptPII(encryptedData: EncryptedPIIData): PIIData
}
```

## Data Models

### Debtor Specialization Model

The system implements EER specialization using the "Class Table Inheritance" pattern where:
- The parent `Debtor` table contains common attributes
- Child tables `Individual_Debtor` and `Corporate_Debtor` contain specialization-specific attributes
- The `debtor_type` discriminator column indicates the specialization type
- Foreign key constraints ensure referential integrity

**Querying Specialized Debtors:**
```sql
-- Get complete Individual Debtor information
SELECT d.*, id.national_id, id.date_of_birth, id.verification_status
FROM Debtor d
JOIN Individual_Debtor id ON d.debtor_id = id.debtor_id
WHERE d.debtor_id = ?;

-- Get complete Corporate Debtor information
SELECT d.*, cd.tax_registration_number, cd.business_type, cd.registration_date
FROM Debtor d
JOIN Corporate_Debtor cd ON d.debtor_id = cd.debtor_id
WHERE d.debtor_id = ?;
```

### Invoice Assignment Model

The system enforces single-agency assignment through database constraints:
- An invoice can have at most one `assigned_agency_id` at any time
- Before assigning to a new agency, the previous assignment must be cleared
- Status transitions enforce business rules (e.g., cannot assign a "Closed" invoice)

### Payment and Commission Model

Commission calculation is automated using generated columns:
```sql
commission_amount DECIMAL(15, 2) GENERATED ALWAYS AS (amount_paid * commission_rate) STORED
```

This ensures:
- Commission is always consistent with payment amount and rate
- No manual calculation errors
- Historical commission rates are preserved per payment

### Transaction Atomicity Model

Payment recording uses database transactions to ensure atomicity:
```sql
BEGIN TRANSACTION;
  -- Insert payment record
  INSERT INTO Payment (...) VALUES (...);
  
  -- Update invoice remaining balance
  UPDATE Invoice SET ... WHERE invoice_id = ?;
  
  -- Check if invoice is fully paid
  IF (remaining_balance <= 0) THEN
    UPDATE Invoice SET status = 'Settled' WHERE invoice_id = ?;
  END IF;
  
  -- Create audit trail entry
  INSERT INTO Audit_Trail (...) VALUES (...);
COMMIT;
```

If any step fails, the entire transaction rolls back.

### Encryption Model

PII fields are encrypted at the application layer before storage:
- Encryption uses AES-256 in GCM mode
- Encryption keys are managed separately from the database
- Decryption occurs only when authorized users request the data
- Encrypted fields: `contact_phone`, `contact_email`, `address`, `national_id`, `tax_registration_number`

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

