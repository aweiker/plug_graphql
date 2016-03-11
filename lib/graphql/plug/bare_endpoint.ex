defmodule GraphQL.Plug.BareEndpoint do
  @moduledoc """
  This is the core plug for mounting a GraphQL server.

  You can build your own pipeline by mounting the
  `GraphQL.Plug.Endpoint` plug directly.

  ```elixir
  forward "/graphql", GraphQL.Plug.Endpoint, schema: {MyApp.Schema, :schema}
  ```

  You may want to look at how `GraphQL.Plug` configures its pipeline.
  Specifically note how `Plug.Parsers` are configured, as this is required
  for pre-parsing the various POST bodies depending on `content-type`.

  This plug currently includes _GraphiQL_ support but this should end
  up in it's own plug.
  """

  import Plug.Conn
  alias Plug.Conn
  alias GraphQL.Plug.RootValue
  alias GraphQL.Plug.Parameters

  @behaviour Plug

  def init(opts) do
    schema = case Keyword.get(opts, :schema) do
      {mod, func} -> apply(mod, func, [])
      s -> s
    end
    root_value = Keyword.get(opts, :root_value, %{})
    %{schema: schema, root_value: root_value}
  end

  def call(%Conn{method: m} = conn, opts) when m in ["GET", "POST"] do
    %{schema: schema, root_value: root_value} = conn.assigns[:graphql_options] || opts

    query = Parameters.query(conn)
    variables = Parameters.variables(conn)
    operation_name = Parameters.operation_name(conn)
    evaluated_root_value = RootValue.evaluate(conn, root_value)

    cond do
      query ->
        handle_call(conn, schema, evaluated_root_value, query, variables, operation_name)
      true ->
        handle_error(conn, "Must provide query string.")
    end
  end

  def call(%Conn{method: _} = conn, _) do
    handle_error(conn, "GraphQL only supports GET and POST requests.")
  end

  def handle_error(conn, message) do
    {:ok, errors} = Poison.encode %{errors: [%{message: message}]}
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(400, errors)
  end

  def handle_call(conn, schema, root_value, query, variables, operation_name) do
    conn
    |> put_resp_content_type("application/json")
    |> execute(schema, root_value, query, variables, operation_name)
  end

  defp execute(conn, schema, root_value, query, variables, operation_name) do
    case GraphQL.execute(schema, query, root_value, variables, operation_name) do
      {:ok, data} ->
        case Poison.encode(data) do
          {:ok, json}      -> send_resp(conn, 200, json)
          {:error, errors} -> send_resp(conn, 400, errors)
        end
      {:error, errors} ->
        case Poison.encode(errors) do
          {:ok, json}      -> send_resp(conn, 400, json)
          {:error, errors} -> send_resp(conn, 400, errors)
        end
    end
  end
end