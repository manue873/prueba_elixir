# Los tests @moduletag :surreal necesitan SurrealDB levantado
# (docker compose up -d) y se excluyen por defecto: mix test --include surreal
ExUnit.start(exclude: [:surreal])
