Built-in engines (no Osaurus). Install once:
  uv venv --python 3.12 ~/.askmymac/venv  && uv pip install --python ~/.askmymac/venv/bin/python "mlx-lm>=0.31"
  uv venv --python 3.12 ~/.askmymac/bvenv && uv pip install --python ~/.askmymac/bvenv/bin/python vmlx==1.6.78 jang==2.5.49 mlx-lm==0.31.3
  cp run-*.sh ~/.askmymac/ && chmod +x ~/.askmymac/run-*.sh
The app starts them with `launchctl submit -l com.tara.askmymac.<spark|bonsai>` and removes them when unselected or on quit.
Spark: port 8095 (mlx_lm.server --trust-remote-code). Bonsai: port 8096 (vmlx-serve). mlx-lm 0.32 breaks vmlx 1.6.78 (SequenceStateMachine), so pin 0.31.3.
