# Script to test the Router and Domain Handler implementation

# Start the Router agent
{:ok, _} = Lang.Router.start_link([])

# Explicitly register domain handlers
Lang.Router.register_domains()

IO.puts("\n--- Registered Domains ---")
registered = Lang.Router.list_domains()
Enum.each(registered, &IO.puts/1)

IO.puts("\n--- Routing Tests ---")

# Test 1: Input that should be handled by Echo domain
input1 = "echo Hello, World!"
IO.puts("\nRouting input: '" <> input1 <> "'")
case Lang.Router.route(input1, %{user_id: "test_user", org_id: "test_org"}) do
  {:ok, result1} -> IO.inspect(result1)
  {:continue, reason1} -> IO.puts("Continued: " <> reason1)
  {:error, error1} -> IO.puts("Error: " <> error1)
end

# Test 2: Input that should fall through to Fallback domain
input2 = "do a barrel roll"
IO.puts("\nRouting input: '" <> input2 <> "'")
case Lang.Router.route(input2, %{user_id: "test_user", org_id: "test_org"}) do
   {:ok, result2} -> IO.inspect(result2)
   {:continue, reason2} -> IO.puts("Continued: " <> reason2)
   {:error, error2} -> IO.puts("Error: " <> error2)
end

# Test 3: Show that the Echo domain now works
IO.puts("\n--- Testing Echo Domain (should work now) ---")
input3 = "echo This should be echoed back!"
IO.puts("\nRouting input: '" <> input3 <> "'")
case Lang.Router.route(input3, %{user_id: "test_user", org_id: "test_org"}) do
  {:ok, result3} -> IO.inspect(result3)
  {:continue, reason3} -> IO.puts("Continued: " <> reason3)
  {:error, error3} -> IO.puts("Error: " <> error3)
end