source=lambda_function.py
binary=function.zip
queue-name=partner-queue.fifo

.PHONY: all
all: clean build

.PHONY: clean
clean:
	rm -f $(binary)

.PHONY: build
build:
	zip -9 $(binary) $(source)

.PHONY: deploy
deploy:
	terraform apply

.PHONY: undeploy
undeploy: test-clean
	terraform destroy

.PHONY: test
test:
	aws s3 cp --recursive test-files/ s3://partner-account-files/
	sleep 10
	aws sqs receive-message --queue-url $$(aws sqs get-queue-url --queue-name=$(queue-name) --output=text) --output=text --max-number-of-messages=10

.PHONY: test-clean
test-clean:
	aws s3 rm --recursive s3://partner-account-files/
	aws sqs purge-queue --queue-url $$(aws sqs get-queue-url --queue-name=$(queue-name) --output=text)

