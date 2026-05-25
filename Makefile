.PHONY: clean_init_db up_db down_db initdb

initdb:
	@mkdir -p initdb
	@cp -r sql/*.sql initdb
	@cp -r scripts/*.sh initdb



clean_init_db:
	@rm -rf initdb

up_db: initdb
	@docker compose up -d --force-recreate

down_db: clean_init_db
	@docker compose down -v
