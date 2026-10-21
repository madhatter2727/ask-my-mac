#!/bin/bash
exec "$HOME/.askmymac/bvenv/bin/vmlx-serve" serve "$HOME/MLXModels/Bonsai-2-27B-JANG-CRACK-1.75bit" --served-model-name bonsai-2-27b --host 127.0.0.1 --port 8096 --enable-auto-tool-choice >>"$HOME/.askmymac/bonsai.log" 2>&1
