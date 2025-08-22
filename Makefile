.PHONY: setup lint test backtest paper logs sample-synth sample-merge

setup:
	uv venv -p python3.11 .venv || python3 -m venv .venv
	. .venv/bin/activate && pip install -U pip wheel && pip install -r requirements.txt

lint:
	. .venv/bin/activate && ruff check . && black --check .

test:
	. .venv/bin/activate && pytest -q

backtest:
	. .venv/bin/activate && python -m src.run_backtest --config configs/backtest.yaml

paper:
	. .venv/bin/activate && python -m src.run_paper --config configs/paper.yaml

logs:
	tail -n 200 -f ./var/log/app.log

sample-synth:
	python3 scripts/data/make_sample.py synth --start 2025-08-20 --days 2 --out data/samples/es_tick_add_1m.csv

# expects data/raw/{es_1m.csv,tick_1m.csv,add_1m.csv} with 'timestamp' in ISO UTC
sample-merge:
	python3 scripts/data/make_sample.py merge --es data/raw/es_1m.csv --tick data/raw/tick_1m.csv --add data/raw/add_1m.csv --out data/samples/es_tick_add_1m.csv

