import csv
import codecs
from collections import defaultdict
import json
import logging
import os
from pathlib import Path
import boto3

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

TABLES = ["clients", "portfolios", "accounts", "transactions"]
QUEUE_NAME = os.environ.get('QUEUE_NAME') or "partner-queue.fifo"

ACTION_TAX = "TAX"
ACTION_DEPOSIT = "DEPOSIT"
ALL_ACTIONS = [ACTION_TAX, ACTION_DEPOSIT]


def build_error(client_reference=None, portfolio_reference=None, account_number=None, message=None):
    if message is None:
        message = "Something went wrong!"
    return {
        "type": "error_message",
        "client_reference": client_reference,
        "portfolio_reference": portfolio_reference,
        "account_number": account_number,
        "message": message
    }


def process_data(data):
    result = []

    # 1. data ingestion and processing
    clients = {}
    for x in data["clients"]:
        client_reference = x["client_reference"]
        try:
            clients[client_reference] = {
                "first_name": x["first_name"],
                "last_name": x["last_name"],
                "client_reference": x["client_reference"],
                "tax_free_allowance": float(x["tax_free_allowance"])
            }
        except Exception as e:
            result.append(build_error(client_reference=client_reference))

    portfolios = defaultdict(list)
    for x in data["portfolios"]:
        client_reference = x["client_reference"]
        try:
            portfolios[client_reference].append({
                "account_number": int(x["account_number"]),
                "portfolio_reference": x["portfolio_reference"],
                "agent_code": x["agent_code"]
            })
        except Exception as e:
            result.append(build_error(
                client_reference=client_reference,
                portfolio_reference=x["portfolio_reference"]
            ))

    accounts = {}
    for x in data["accounts"]:
        account_number = x["account_number"]
        try:
            account_number = int(account_number)
            accounts[account_number] = {
                "cash_balance": float(x["cash_balance"]),
                "currency": x["currency"],
                "taxes_paid": float(x["taxes_paid"])
            }
        except Exception as e:
            result.append(build_error(
                account_number=account_number,
                portfolio_reference=x["portfolio_reference"]
            ))

    transactions = defaultdict(list)
    for x in data["transactions"]:
        account_number = x["account_number"]
        try:
            account_number = int(account_number)
            assert x["keyword"] in ALL_ACTIONS
            transactions[account_number].append({
                "transaction_reference": x["transaction_reference"],
                "amount": float(x["amount"]),
                "keyword": x["keyword"]
            })
        except Exception as e:
            result.append(build_error(
                account_number=account_number,
                portfolio_reference=x["portfolio_reference"]
            ))

    # 2. actual processing
    # NB: we are iterating of each client
    for client_reference, client in clients.items():
        taxes_paid = 0
        try:
            # NB: we assume client has several portfolios
            for portfolio in portfolios.get(client_reference):
                account_number = portfolio["account_number"]
                account = accounts[account_number]
                taxes_paid += account["taxes_paid"]

                # NB: we assume, that account could have no transactions, that's why default
                portfolio_trans = transactions.get(account_number, [])
                # NB: we need to count only "deposit" transactions
                deposits = [x for x in portfolio_trans if x["keyword"] == ACTION_DEPOSIT]

                result.append({
                    "type": "portfolio_message",
                    "portfolio_reference": portfolio["portfolio_reference"],
                    "cash_balance": account["cash_balance"],
                    "number_of_transactions": len(portfolio_trans),
                    "sum_of_deposits": len(deposits)
                })

            result.append({
                "type": "client_message",
                "client_reference": client_reference,
                "tax_free_allowance": client["tax_free_allowance"],
                "taxes_paid": taxes_paid
            })

        except Exception as e:
            # NB: in case of error message will contains exception text
            result.append(build_error(
                client_reference=client_reference,
                message=str(e)
            ))

    return result



def lambda_handler(event, context):
    s3 = boto3.client("s3")
    sqs = boto3.client("sqs")

    bucket_name = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']

    filepath = Path(key)
    name, date = filepath.stem.split("_")

    data = {}
    for table in TABLES:
        key = "{0}_{1}.csv".format(table, date)
        try:
            data[table] = s3.get_object(Bucket=bucket_name, Key=key)["Body"]
        except s3.exceptions.NoSuchKey as e:
            log.warning("{0} is not yet available. Exiting...".format(key))
            return

    for table in TABLES:
        data[table] = [row for row in csv.DictReader(codecs.getreader("utf-8")(data[table]))]

    events = process_data(data)

    queue_url = sqs.get_queue_url(QueueName=QUEUE_NAME)['QueueUrl']

    for event in events:
        sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=json.dumps(event),
            MessageGroupId='messageGroup1'
        )
