#export FPCO_CI_REGISTRY_IMAGE ?= registry.gitlab.fpcomplete.com/chrisallen/totto
#export CI_REGISTRY_IMAGE ?= registry.gitlab.com/bitemyapp/totto
#export FPCO_DOCKER_IMAGE ?= ${FPCO_CI_REGISTRY_IMAGE}:latest
#export KUBE_SPEC = etc/kubernetes/totto.yaml
#export DOCKER_IMAGE ?= ${CI_REGISTRY_IMAGE}:latest

export CI_PIPELINE_ID ?= $(shell date +"%Y-%m-%d-%s")
export SERVER_DOCKER_IMAGE ?= gluk64/franklin:server
export PROVER_DOCKER_IMAGE ?=gluk64/franklin:prover
export GETH_DOCKER_IMAGE ?= gluk64/franklin:geth

docker-options = --rm -v $(shell pwd):/home/rust/src -v cargo-git:/home/rust/.cargo/git -v cargo-registry:/home/rust/.cargo/registry
rust-musl-builder = @docker run $(docker-options) -it ekidd/rust-musl-builder

confirm_action:
	@bin/.confirm_action

# Scripts (for shell autocomplete)
env:
db-setup:
db-test:

yarn:
	@cd contracts; yarn
	@cd js/franklin; yarn
	@cd js/client; yarn
	@cd js/loadtest; yarn

client:
	@cd js/client; yarn dev

prover:
	@bin/.load_keys; cargo run --release --bin prover

server:
	@cargo run --release --bin server

sandbox:
	@cd src/sandbox; cargo run

deploy-contracts: confirm_action
	@bin/deploy-contracts

db-reset: confirm_action
	@echo Resetting $(DATABASE_URL)
	@cd src/storage; diesel database reset

redeploy: deploy-contracts db-reset

db-drop: confirm_action
	# this is used to clear the produciton db; cannot do `diesel database reset` because we don't own the db
	@psql $DATABASE_URL -c 'DROP OWNED BY CURRENT_USER CASCADE'
	@src/storage; diesel migration run

build-target:
	$(rust-musl-builder) cargo build --release

clean-target:
	$(rust-musl-builder) cargo clean

server-image: build-target
	docker build -t "${SERVER_DOCKER_IMAGE}" -f ./docker/server/Dockerfile .

prover-image: build-target
	docker build -t "${PROVER_DOCKER_IMAGE}" -f ./docker/prover/Dockerfile .

images: server-image prover-image

push: images
	docker push gluk64/franklin:server
	docker push gluk64/franklin:prover

start: images
	@docker-compose up -d --scale prover=1 server prover

stop:
	@docker-compose stop server prover

status:
	@curl $(API_SERVER)/api/v0.1/status; echo

restart: stop start logs

logs:
	@docker-compose logs -f server prover

dev-up:
	@docker-compose up -d postgres geth

dev-down:
	@docker-compose stop postgres geth

geth:
	@docker build -t "${GETH_DOCKER_IMAGE}" ./docker/geth

geth-up: geth
	@docker-compose up geth

blockscout-migrate:
	@docker-compose up -d blockscout_postgres
	@docker-compose run blockscout /bin/sh -c "echo $MIX_ENV && mix do ecto.drop --force, ecto.create, ecto.migrate"

blockscout-up:
	@docker-compose up -d blockscout_postgres blockscout

blockscout-down:
	@docker-compose stop blockscout blockscout_postgres

# Loadtest

run-loadtest:
	cd js/loadtest; yarn test
