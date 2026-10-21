#!/bin/bash
exec "$HOME/.askmymac/venv/bin/mlx_lm.server" --model "$HOME/MLXModels/Spark-X2.5-4B-MLX-4bit" --trust-remote-code --host 127.0.0.1 --port 8095 >>"$HOME/.askmymac/spark.log" 2>&1
