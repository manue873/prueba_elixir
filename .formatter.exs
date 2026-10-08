[
  import_deps: [:phoenix],
  # DSL de PruebaElixir.Surreal.Schema sin paréntesis, como Ecto.
  locals_without_parens: [surreal_schema: 2, field: 2, field: 3, timestamps: 0],
  inputs: ["*.{ex,exs}", "{config,lib,test}/**/*.{ex,exs}"]
]
