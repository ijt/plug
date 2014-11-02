defmodule Plug.Session.COOKIE do
  @moduledoc """
  Stores the session in a cookie.

  This cookie store is based on `Plug.Crypto.MessageVerifier`
  and `Plug.Crypto.Message.Encryptor` which encrypts and signs
  each cookie to ensure they can't be read nor tampered with.

  Since this store uses crypto features, it requires you to
  set the `:secret_key_base` field in your connection. This
  can be easily achieved with a plug:

      plug :put_secret_key_base

      def put_secret_key_base(conn, _) do
        put_in conn.secret_key_base, "-- LONG STRING WITH AT LEAST 64 BYTES --"
      end

  ## Options

  * `:encrypt` - specify whether to encrypt cookies, defaults to true.
    When this option is false, the cookie is still signed, meaning it
    can't be tempered with but its contents can be read;

  * `:encryption_salt` - a salt used with `conn.secret_key_base` to generate
    a key for encrypting/decrypting a cookie;

  * `:signing_salt` - a salt used with `conn.secret_key_base` to generate a
    key for signing/verifying a cookie;

  * `:key_iterations` - option passed to `Plug.Crypto.KeyGenerator`
    when generating the encryption and signing keys. Defaults to 1000;

  * `:key_length` - option passed to `Plug.Crypto.KeyGenerator`
    when generating the encryption and signing keys. Defaults to 32;

  * `:key_digest` - option passed to `Plug.Crypto.KeyGenerator`
    when generating the encryption and signing keys. Defaults to `:sha256'.



  ## Examples

      # Use the session plug with the table name
      plug Plug.Session, store: :cookie,
                         key: "_my_app_session",
                         encryption_salt: "cookie store encryption salt",
                         signing_salt: "cookie store signing salt",
                         key_length: 64
  """

  @behaviour Plug.Session.Store

  alias Plug.Crypto.KeyGenerator
  alias Plug.Crypto.MessageVerifier
  alias Plug.Crypto.MessageEncryptor

  def init(opts) do
    encryption_salt = check_encryption_salt(opts)
    signing_salt = check_signing_salt(opts)

    iterations = Keyword.get(opts, :key_iterations, 1000)
    length = Keyword.get(opts, :key_length, 32)
    digest = Keyword.get(opts, :key_digest, :sha256)
    key_opts = [iterations: iterations,
                length: length,
                digest: digest,
                cache: Plug.Keys]

    %{encryption_salt: encryption_salt,
      signing_salt: signing_salt,
      key_opts: key_opts}
  end

  def get(conn, cookie, opts) do
    key_opts = opts.key_opts
    if key = opts.encryption_salt do
      MessageEncryptor.verify_and_decrypt(cookie,
                                          derive(conn, key, key_opts),
                                          derive(conn, opts.signing_salt, key_opts))
    else
      MessageVerifier.verify(cookie, derive(conn, opts.signing_salt, key_opts))
    end |> decode()
  end

  def put(conn, _sid, term, opts) do
    binary = encode(term)
    key_opts = opts.key_opts
    if key = opts.encryption_salt do
      MessageEncryptor.encrypt_and_sign(binary,
                                        derive(conn, key, key_opts),
                                        derive(conn, opts.signing_salt, key_opts))
    else
      MessageVerifier.sign(binary, derive(conn, opts.signing_salt, key_opts))
    end
  end

  def delete(_conn, _sid, _opts) do
    :ok
  end

  defp encode(term), do:
    :erlang.term_to_binary(term)

  defp decode({:ok, binary}), do:
    {nil, :erlang.binary_to_term(binary)}
  defp decode(:error), do:
    {nil, %{}}

  defp derive(conn, key, key_opts) do
    conn.secret_key_base
    |> validate_secret_key_base()
    |> KeyGenerator.generate(key, key_opts)
  end

  defp validate_secret_key_base(nil), do:
    raise(ArgumentError, "cookie store expects conn.secret_key_base to be set")
  defp validate_secret_key_base(secret_key_base) when byte_size(secret_key_base) < 64, do:
    raise(ArgumentError, "cookie store expects conn.secret_key_base to be at least 64 bytes")
  defp validate_secret_key_base(secret_key_base), do:
    secret_key_base

  defp check_signing_salt(opts) do
    case opts[:signing_salt] do
      nil  -> raise ArgumentError, "cookie store expects :signing_salt as option"
      salt -> salt
    end
  end

  defp check_encryption_salt(opts) do
    if Keyword.get(opts, :encrypt, true) do
      case opts[:encryption_salt] do
        nil  -> raise ArgumentError, "encrypted cookie store expects :encryption_salt as option"
        salt -> salt
      end
    end
  end
end
