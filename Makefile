.DEFAULT_GOAL := help
COVERPKG := $(shell eval go list ./... | grep -v mocks |  paste -sd "," -)

.PHONY: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: download
download:
	@cd tools/ && go mod download

.PHONY: install-tools
install-tools: download ## Install developer tooling
	@cd tools && go list -f '{{range .Imports}}{{.}} {{end}}' tools.go | CGO_ENABLED=0 xargs go install -mod=readonly

.PHONY: lint
lint:  ## Lint Go source files
	@golangci-lint run

.PHONY: clean
clean: ## Clean files
	rm ./openfga

.PHONY: build
build: ## Build the OpenFGA service
	go build -o ./openfga ./cmd/openfga

.PHONY: run
run: build ## Run the OpenFGA server with in-memory storage
	./openfga run


.PHONY: start-postgres-container
start-postgres-container: ## Start a Postgres Docker container
	docker run -d --name postgres -p 5432:5432 -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=password postgres:14
	@echo \> use \'postgres://postgres:password@localhost:5432/postgres\' to connect to postgres

.PHONY: migrate-postgres
migrate-postgres: build ## Run Postgres migrations
	# nosemgrep: detected-username-and-password-in-uri
	./openfga migrate --datastore-engine postgres --datastore-uri 'postgres://postgres:password@localhost:5432/postgres'

.PHONY: run-postgres
run-postgres: build ## Run the OpenFGA server with Postgres storage
	./openfga run --datastore-engine postgres --datastore-uri 'postgres://postgres:password@localhost:5432/postgres'

.PHONY: start-mysql-container
start-mysql-container: build ## Start a MySQL Docker container
	docker run -d --name mysql -p 3306:3306 -e MYSQL_ROOT_PASSWORD=secret -e MYSQL_DATABASE=openfga mysql:8
	
.PHONY: migrate-mysql
migrate-mysql: build ## Run MySQL migrations
	# nosemgrep: detected-username-and-password-in-uri
	./openfga migrate --datastore-engine mysql --datastore-uri 'root:secret@tcp(localhost:3306)/openfga?parseTime=true'

.PHONY: run-mysql
run-mysql: build ## Run the OpenFGA server with MySQL storage
	./openfga run --datastore-engine mysql --datastore-uri 'root:secret@tcp(localhost:3306)/openfga?parseTime=true'

.PHONY: go-generate
go-generate: install-tools
	go generate ./...

.PHONY: unit-test
unit-test: go-generate ## Run unit tests
	go test $(gotest_extra_flags) -race -v \
			-coverprofile=coverageunit.out \
			-coverpkg=$(COVERPKG) \
			-covermode=atomic -race \
			-count=1 \
			./...

build-functional-test-image: ## Build Docker image needed to run functional tests
	docker build -t="openfga/openfga:functionaltest" .

.PHONY: functional-test
functional-test: ## Run functional tests (needs build-functional-test-image)
	go test $(gotest_extra_flags) -v \
			-coverprofile=coveragefunctional.out \
			-coverpkg=$(COVERPKG) \
			-covermode=atomic -race \
			-count=1 \
			-tags=functional \
			./cmd/openfga/...

.PHONY: bench
bench: go-generate
	go test ./... -bench=. -run=XXX -benchmem
