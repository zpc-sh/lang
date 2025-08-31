%{
  configs: [
    %{
      name: "custom",
      files: %{
        included: ["lib/", "test/", "mix.exs"],
        excluded: ["_build/", "deps/", "native/", "priv/"]
      },
      checks: [
        {CredoChecks.NoSingleBackslashDefaults, []}
      ]
    }
  ]
}

