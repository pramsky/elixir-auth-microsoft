defmodule ElixirAuthMicrosoft do
  @moduledoc """
  A simple, minimalist Microsoft OAuth Authentication for Elixir Apps.
  Tested, documented and maintained. Offers simple access to tokens and basic user profile information.
  """

  @authorize_url "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
  @token_url "https://login.microsoftonline.com/common/oauth2/v2.0/token"
  @profile_url "https://graph.microsoft.com/v1.0/me"
  @default_scope "https://graph.microsoft.com/User.Read"
  @default_callback_path "/auth/microsoft/callback"


  @httpoison (Application.compile_env(:elixir_auth_microsoft, :httpoison_mock) && ElixirAuthMicrosoft.HTTPoisonMock) || HTTPoison

  @doc """
  `http/0` injects a TestDouble in test envs.
  When testing, it uses a mocked version of HTTPoison with predictible results. When in production, it uses the original version.
  """
  def http, do: @httpoison

  @doc """
  `generate_oauth_url_authorize/1` creates an OAuth2 URL with client_id, redirect_uri and scopes (be sure to create the app registration in Azure Portal AD).
  The redirect_uri will be the URL Microsoft will redirect after successful sign-in.
  This is the URL that you should be used in a "Login with Microsoft"-type button.
  """
  @spec generate_oauth_url_authorize(Conn.t()) :: String.t()
  def generate_oauth_url_authorize(conn) do
    query = %{
      client_id: microsoft_client_id(),
      response_type: "code",
      redirect_uri: generate_redirect_uri(conn),
      scope: get_microsoft_scopes(),
      response_mode: "query"
    }

    params = URI.encode_query(query, :rfc3986)
    "#{@authorize_url}?&#{params}"
  end

  @doc """
  `generate_oauth_url_authorize/2` is the same as `generate_oauth_url_authorize/1` but with a state parameter.
  This state parameter should be compared with the one that is sent as query param in the redirect URI after the sign-in is successful.
  """
  @spec generate_oauth_url_authorize(%{:host => any, optional(any) => any}, binary) :: String.t()
  def generate_oauth_url_authorize(conn, state) when is_binary(state) do
    params = URI.encode_query(%{state: state}, :rfc3986)
    generate_oauth_url_authorize(conn) <> "&#{params}"
  end

  @doc """
  `get_token/2` fetches the ID token using the authorization code that was previously obtained.
  Env variables are used to encode information while fetching the ID token from Microsoft, including the registered client ID that was created in Azure Portal AD.
  """
  @spec get_token(String.t(), Conn.t()) :: {:ok, map} | {:error, any}
  def get_token(code, conn) do
    headers = ["Content-Type": "multipart/form-data"]

    # We don't encode with JSON because the endpoint only works properly with uriencoded form data
    body = [
      {"grant_type", "authorization_code"},
      {"client_id", microsoft_client_id()},
      {"redirect_uri", generate_redirect_uri(conn)},
      {"code", code},
      {"scope", get_microsoft_scopes()},
      {"client_secret", microsoft_client_secret()}
    ]

    http().post(@token_url, {:multipart, body}, headers)
    |>parse_body_response()

  end

  @doc """
  `get_user_profile/1` fetches the signed-in Microsoft User info according to the token that is passed by calling `get_token/1`.
  """
  @spec get_user_profile(String.t()) :: {:error, any} | {:ok, map}
  def get_user_profile(token) do
    headers = ["Authorization": "Bearer #{token}", "Content-Type": "application/json"]

    http().get(@profile_url, headers)
    |> parse_body_response()

  end

  @doc """
  `parse_body_response/1` parses the response from Microsoft's endpoints.
  The keys of the decoded map are converted in atoms, for easier access in templates.

  ##TODO check cases where the parsed code when fetching fails.
  """
  @spec parse_body_response({atom, String.t()} | {:error, any}) :: {:ok, map} | {:error, any}
  def parse_body_response({:error, err}), do: {:error, err}
  def parse_body_response({:ok, response}) do
    body = Map.get(response, :body)

    if body == nil do
      {:error, :no_body}
    else
      {:ok, str_key_map} = Jason.decode(body)
      atom_key_map = for {key, val} <- str_key_map, into: %{}, do: {String.to_atom(key), val}
      {:ok, atom_key_map}
    end
  end


  defp generate_redirect_uri(conn) do
    get_baseurl_from_conn(conn) <> get_callback_path()
  end

  defp get_microsoft_scopes do
    System.get_env("MICROSOFT_SCOPES_LIST") || Application.get_env(:elixir_auth_microsoft, :scopes) || @default_scope
  end

  defp microsoft_client_secret do
    System.get_env("MICROSOFT_CLIENT_SECRET") || Application.get_env(:elixir_auth_microsoft, :client_id)
  end

  defp microsoft_client_id do
    System.get_env("MICROSOFT_CLIENT_ID") || Application.get_env(:elixir_auth_microsoft, :client_secret)
  end

  defp get_callback_path do
    System.get_env("MICROSOFT_CALLBACK_PATH") || @default_callback_path
  end


  defp get_baseurl_from_conn(%{host: h, port: p}) when h == "localhost" do
    "http://#{h}:#{p}"
  end

  defp get_baseurl_from_conn(%{host: h}) do
    "https://#{h}"
  end

end
