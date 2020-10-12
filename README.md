# AWS Serverless ETL

This ETL pipeline takes input in CSV
format from an S3 bucket and to produce output in JSON format for internal processing, sending it to a queue (SQS).

## Usage

### Build
```make```

### Deploy
```make deploy```

### Test
```make test```

### Undeploy
```make undeploy```


## Process Overview
1. The partner uploads 4 files to a shared S3 bucket daily. The object keys have the
form $TYPE_$DATE.csv, e.g. clients_20200130.csv.
    * clients: List of all clients. A client can have multiple portfolios.
    * portfolios: List of all portfolios.
    * acounts: List of all bank accounts. A portfolio has exactly one bank account.
    * transactions: List of all transactions on managed portfolios.
2. As soon as complete data is available (all 4 files), AWS Lambda function process the input, generate messages in JSON format and send them to a specified message queue in SQS. The expected output is:
    * Exactly one client message per client. Taxes paid is the sum across all accounts held by the client.
    * Exactly one portfolio message per portfolio.
    * Any number of error messages in case of unexpected inputs.


## Data Model

### Input files (CSV)
* ___clients___

record_id|first_name|last_name|client_reference|tax_free_allowance
---|---|---|---|---:  
1|Frida|Müller|9e40659b-8b9f-4fc4-814b-5a7b5a23b64d|801
2|Fritz|Maier|f4a0cc2c-d0b4-4f14-b202-c8a5e45e90e7|0

* ___portfolios___

record_id|account_number|portfolio_reference|client_reference|agent_code
---|---|---|---|---|---
1|12345678|90755e32-7438-4354-ad37-ad900e297844|9e40659b-8b9f-4fc4-814b-5a7b5a23b64d|EREZBT
2|12345679|439695b4-508d-4562-8576-670e70024627|f4a0cc2c-d0b4-4f14-b202-c8a5e45e90e7|SFOJFK

* ___accounts___

record_id|account_number|cash_balance|currency|taxes_paid
---|---|---:|---|---:
1|12345678|15000.00|EUR|0.00
2|12345679|-56.00|EUR|789.56

* ___transactions___

record_id|account_number|transaction_reference|amount|keyword
---|---|---|---:|---
1|12345678|14e56786|5000|DEPOSIT
2|12345679|dfeb5fe13cd4|-789.56|TAX

### Output messages (JSON)

___client message___
```json
{
  "type": "client_message",
  "client_reference": "ec4e727b-65bf-4d0b-b2cc-34c3f89b8270"
  "tax_free_allowance": 801
  "taxes_paid": 0
}
```

___portfolio message:___
```json
{
  "type": "portfolio_message",
  "portfolio_reference": "90755e32-7438-4354-ad37-ad900e297844",
  "cash_balance": 15000,
  "number_of_transactions": 15,
  "sum_of_deposits": 5000
}
```

___error message:___
```json
{
  "type": "error_message",
  "client_reference": null,
  "portfolio_reference": "90755e32-7438-4354-ad37-ad900e297844",
  "message": "Something went wrong!"
}
```