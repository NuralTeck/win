# PRIVACY POLICY (गोपनीयता नीति)
**Last Updated: September 2026**
**Applicable Software: PhantomManagement / OpsCore Pro (Desktop & ERP Edition)**

---

### 1. COMMITMENT TO DATA PRIVACY & SOVEREIGNTY
**PhantomManagement / OpsCore Pro** ("the Software") is built on a strict **Offline-First, Privacy-by-Design** architecture. We respect your business confidentiality and believe that your stock ledgers, financial figures, customer contact lists, and transaction histories belong entirely to you.

---

### 2. LOCAL DATA STORAGE (100% OFFLINE DATABASE)
1. **Local SQLite Storage:** All business data—including ticket sales records, stock issue vouchers, unsold ticket return lists, dealer and sub-seller directories, lottery results, and financial hisab ledgers—is saved exclusively in an offline SQLite database (`opscore_pro.db`) on your local personal computer / host machine.
2. **No Cloud Data Harvesting:** We do **NOT** copy, synchronize, harvest, or transmit your database records, accounts, or personal information to any central cloud server or third-party servers.
3. **Database Ownership:** You maintain 100% ownership and control over your database files and local backups.

---

### 3. INFORMATION PROCESSED BY THE APPLICATION
During routine usage, the Software processes the following categories of data strictly within your local environment:
* **Business Contact Information:** Dealer names, sub-seller names, customer names, and contact phone numbers provided by you for voucher and invoice generation.
* **Transaction Records:** Ticket series, ticket number ranges, issue dates, draw shifts (e.g., Dear 1 PM, 6 PM, 8 PM), quantities, purchase rates, and billing totals.
* **Scan & OCR Images:** Digital images of parchas, vouchers, or results selected from your local storage. Image analysis is performed locally or through an ephemeral, stateless API connection solely for character recognition (OCR), without persistent cloud retention of your image content.
* **Application Settings:** Local preferences, user roles, security PINs, and system configuration parameters.

---

### 4. THIRD-PARTY SERVICES & TELEMETRY
* **Zero Commercial Telemetry:** The Software does not include third-party ad networks, behavioural trackers, analytics beacons, or data monetization libraries.
* **Optional Integrations:** 
  * If you configure optional local messaging services (such as a local WhatsApp automation bridge or SMS gateway), messages and exported hisab slips are transmitted solely through your own authorized accounts and communication channels.
  * If you configure an external AI OCR key (e.g., Google Gemini API), image payloads are sent encrypted via HTTPS solely for automated text parsing in accordance with standard API privacy standards and are not utilized to profile your business.

---

### 5. DATA SECURITY & BEST PRACTICES
1. **Host-Level Protection:** Because the data resides on your local storage, we recommend maintaining operating system security updates, installing antivirus protection, and restricting unauthorized physical or network access to the host machine.
2. **Access Control:** The Software incorporates role-based access control and security PIN features to prevent unauthorized personnel from viewing sensitive party hisabs or modifying price matrices.
3. **Backup Responsibility:** You are encouraged to create regular local backups of your `opscore_pro.db` database to secure external media or encrypted drives.

---

### 6. DATA RETENTION & DELETION
* **User-Driven Data Lifecycles:** Data remains on your computer until you choose to modify, archive, or delete it.
* **Master System Reset (Wipe):** The Software includes an administrative "Master System Reset" function that permits authorized administrators to permanently purge operational records, vouchers, and unsold entries directly from the local disk at will.

---

### 7. CONTACT & INQUIRIES
For any technical inquiries or compliance clarifications concerning this Privacy Policy, please contact your authorized system administrator or technical representative.
