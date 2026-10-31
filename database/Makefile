.PHONY: certs up init status sql down package
certs:
	./scripts/generate-certs.sh local
up:
	docker compose up -d
init:
	./scripts/init-cluster.sh node1
status:
	./scripts/status.sh
sql:
	./scripts/sql.sh node1
down:
	docker compose stop -t 300
package:
	./scripts/package.sh
