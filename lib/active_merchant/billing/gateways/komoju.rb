require 'json'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class KomojuGateway < Gateway
      self.test_url = "https://sandbox.komoju.com/api/v1"
      self.live_url = "https://komoju.com/api/v1"
      self.supported_countries = ['JP']
      self.default_currency = 'JPY'
      self.money_format = :cents
      self.homepage_url = 'https://www.komoju.com/'
      self.display_name = 'Komoju'
      self.supported_cardtypes = [:visa, :master, :american_express, :jcb]

      STANDARD_ERROR_CODE_MAPPING = {
        "bad_verification_value" => "incorrect_cvc",
        "card_expired" => "expired_card",
        "card_declined" => "card_declined",
        "invalid_number" => "invalid_number"
      }

      def initialize(options = {})
        requires!(options, :login)
        super
      end

      def continue(uuid, payment_details)
        details = {payment_details: payment_details}
        commit("/payments/#{uuid}", details, :patch)
      end

      def purchase(money, payment, options = {})
        post = {}
        post[:amount] = amount(money)
        post[:locale] = options[:locale] if options[:locale]
        post[:description] = options[:description]
        add_payment_details(post, payment, options)
        post[:currency] = options[:currency] || default_currency
        post[:external_order_num] = options[:order_id] if options[:order_id]
        post[:tax] = options[:tax] if options[:tax]
        add_fraud_details(post, options)

        commit("/payments", post)
      end

      def refund(amount, identification, options = {})
        params = { :amount => amount }
        commit("/payments/#{identification}/refund", params)
      end

      def void(identification, options = {})
        commit("/payments/#{identification}/refund", {})
      end

      def store(payment, options = {})
        post = {}
        add_payment_details(post, payment, options)

        if options[:customer_profile]
          post[:email] = options[:email]
          commit("/customers", post)
        else
          commit("/tokens", post)
        end
      end

      private

      def add_payment_details(post, payment, options)
        case payment
        when CreditCard
          details = {}

          details[:type] = 'credit_card'
          details[:number] = payment.number
          details[:month] = payment.month
          details[:year] = payment.year
          details[:verification_value] = payment.verification_value
          details[:given_name] = payment.first_name
          details[:family_name] = payment.last_name
          details[:email] = options[:email] if options[:email]
          post[:payment_details] = details
        when String
          if payment.match(/^tok_/)
            post[:payment_details] = payment
          else
            post[:customer] = payment
          end
        else
          post[:payment_details] = payment
        end
      end

      def add_fraud_details(post, options)
        details = {}

        details[:customer_ip] = options[:ip] if options[:ip]
        details[:customer_email] = options[:email] if options[:email]
        details[:browser_language] = options[:browser_language] if options[:browser_language]
        details[:browser_user_agent] = options[:browser_user_agent] if options[:browser_user_agent]

        post[:fraud_details] = details unless details.empty?
      end

      def api_request(method, path, data)
        raw_response = nil
        begin
          raw_response = ssl_request(method, "#{url}#{path}", data, headers)
        rescue ResponseError => e
          raw_response = case e.response.code.to_i
          when 504
            {error: {code: "gateway_timeout", message: Spree.t(:payment_processing_failed)}}.to_json
          else
            e.response.body
          end
        end

        JSON.parse(raw_response)
      end

      def commit(path, params, method = :post)
        response = api_request(method, path, params.to_json)
        success = !response.key?("error")
        message = (success ? "Transaction succeeded" : response["error"]["message"])
        Response.new(
          success,
          message,
          response,
          test: test?,
          error_code: (success ? nil : error_code(response["error"]["code"])),
          authorization: (success ? response["id"] : nil)
        )
      end

      def error_code(code)
        STANDARD_ERROR_CODE_MAPPING[code] || code
      end

      def url
        test? ? self.test_url : self.live_url
      end

      def headers
        {
          "Authorization" => "Basic " + Base64.encode64(@options[:login].to_s + ":").strip,
          "Accept" => "application/json",
          "Content-Type" => "application/json",
          "User-Agent" => "Komoju/v1 ActiveMerchantBindings/#{ActiveMerchant::VERSION}"
        }
      end
    end
  end
end
