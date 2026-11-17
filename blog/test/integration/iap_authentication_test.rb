require "test_helper"

class IapAuthenticationTest < ActionDispatch::IntegrationTest
  test "auto-authenticates and creates user when IAP header is present" do
    assert_difference("User.count", 1) do
      get new_post_url, headers: { "X-Goog-Authenticated-User-Email" => "accounts.google.com:student@example.com" }
    end

    assert_response :success
    created_user = User.find_by(email_address: "student@example.com")
    assert_not_nil created_user
    assert_equal "iap", created_user.created_via
    assert_equal "Auto-generated as logged in from IAP allow listed users", created_user.description
    assert cookies[:session_id]

    assert_includes response.body, "Login recognized by IAP -&gt; User ##{created_user.id} (#{created_user.email_address}) just created!"
  end


  test "auto-authenticates existing user when IAP header matches" do
    existing_user = users(:one)

    assert_no_difference("User.count") do
      get new_post_url, headers: { "X-Goog-Authenticated-User-Email" => existing_user.email_address }
    end

    assert_response :success
    assert cookies[:session_id]
    assert_includes response.body, "Login recognized by IAP -&gt; User ##{existing_user.id} (#{existing_user.email_address})"
  end

  test "redirects to login when no IAP header is present and unauthenticated" do
    get new_post_url
    assert_redirected_to new_session_url
  end

  test "respects IAP_MOCK_EMAIL in test environment and displays fake IAP warning banner" do
    ENV["IAP_MOCK_EMAIL"] = "simulated-iap-account@example.com"
    begin
      assert_difference("User.count", 1) do
        get new_post_url
      end
      assert_response :success
      assert_not_nil User.find_by(email_address: "simulated-iap-account@example.com")
      assert_includes response.body, "This is a fake IAP login based on ENV[IAP_MOCK_EMAIL]"
      assert_includes response.body, "do NOT use in prod"
    ensure
      ENV.delete("IAP_MOCK_EMAIL")
    end
  end

  test "blocks IAP user not in IAP_ALLOWED_USERS" do
    ENV["IAP_ALLOWED_USERS"] = "student@example.com,admin@example.com"
    begin
      assert_no_difference("User.count") do
        get new_post_url, headers: { "X-Goog-Authenticated-User-Email" => "accounts.google.com:unauthorized@example.com" }
      end
      assert_redirected_to new_session_url
    ensure
      ENV.delete("IAP_ALLOWED_USERS")
    end
  end

  test "allows IAP user in IAP_ALLOWED_USERS" do
    ENV["IAP_ALLOWED_USERS"] = "student@example.com,admin@example.com,allowed-user@example.com"
    begin
      assert_difference("User.count", 1) do
        get new_post_url, headers: { "X-Goog-Authenticated-User-Email" => "accounts.google.com:allowed-user@example.com" }
      end
      assert_response :success
      assert_not_nil User.find_by(email_address: "allowed-user@example.com")
    ensure
      ENV.delete("IAP_ALLOWED_USERS")
    end
  end
end

