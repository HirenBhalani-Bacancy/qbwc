$:<< File.expand_path(File.dirname(__FILE__) + '/../..')
require 'test_helper.rb'

class ResponseTest < ActionDispatch::IntegrationTest

  def setup
    ResponseTest.app = Rails.application
    QBWC.clear_jobs

    $HANDLE_RESPONSE_DATA = nil
    $HANDLE_RESPONSE_IS_PASSED_DATA = false
  end

  class HandleResponseWithDataWorker < QBWC::Worker
    def requests(job)
      {:customer_query_rq => {:full_name => 'Quincy Bob William Carlos'}}
    end
    def handle_response(response, job, request, data)
      $HANDLE_RESPONSE_IS_PASSED_DATA = (data == $HANDLE_RESPONSE_DATA)
    end
  end

  test "handle_response is passed data" do
    $HANDLE_RESPONSE_DATA = {:first => {:second => 2, :third => '3'} }
    $HANDLE_RESPONSE_IS_PASSED_DATA = false
    QBWC.add_job(:integration_test, true, '', HandleResponseWithDataWorker, nil, $HANDLE_RESPONSE_DATA)
    session = QBWC::Session.new('foo', '')
    assert_not_nil session.next_request
    simulate_response(session)
    assert_nil session.next_request
    assert $HANDLE_RESPONSE_IS_PASSED_DATA
  end

  class HandleResponseOmitsJobWorker < QBWC::Worker
    def requests(job)
      {:customer_query_rq => {:full_name => 'Quincy Bob William Carlos'}}
    end
    def handle_response(*response)
      $HANDLE_RESPONSE_EXECUTED = true
    end
  end

  test "handle_response must use splat operator when omitting job argument" do
    $HANDLE_RESPONSE_EXECUTED = false
    QBWC.add_job(:integration_test, true, '', HandleResponseOmitsJobWorker)
    session = QBWC::Session.new('foo', '')
    assert_not_nil session.next_request
    simulate_response(session)
    assert_nil session.next_request
    assert $HANDLE_RESPONSE_EXECUTED
  end

  class QueryAndDeleteWorker < QBWC::Worker
    def requests(job)
      {:name => 'mrjoecustomer'}
    end

    def handle_response(resp, job, request, data)
       QBWC.delete_job(job.name)
    end
  end

  test "processes warning responses and deletes the job" do

    # Add a job
    QBWC.add_job(:query_joe_customer, true, COMPANY, QueryAndDeleteWorker)

    # Simulate controller receive_response
    ticket_string = QBWC::ActiveRecord::Session.new(QBWC_USERNAME, COMPANY).ticket
    session = QBWC::Session.new(nil, COMPANY)

    session.response = QBWC_CUSTOMER_QUERY_RESPONSE_WARN
    assert_equal 100, session.progress
    assert_equal '500', session.status_code
    assert_equal 'Warn', session.status_severity

    # Simulate arbitrary controller action
    session = QBWC::ActiveRecord::Session.get(ticket_string)  # simulated get_session
    session.save  # simulated save_session

  end

  test "processes error responses and deletes the job" do

    # Add a job
    QBWC.add_job(:query_joe_customer, true, COMPANY, QueryAndDeleteWorker)

    # Simulate controller receive_response
    ticket_string = QBWC::ActiveRecord::Session.new(QBWC_USERNAME, COMPANY).ticket
    session = QBWC::Session.new(nil, COMPANY)

    session.response = QBWC_CUSTOMER_QUERY_RESPONSE_ERROR
    assert_equal 0, session.progress
    assert_equal '3120', session.status_code
    assert_equal 'Error', session.status_severity
    assert_equal 'QBWC ERROR: 3120 - Object "8000001B-1405768916" specified in the request cannot be found.  QuickBooks error message: Invalid argument.  The specified record does not exist in the list.', session.error

    # Simulate controller get_last_error
    session = QBWC::ActiveRecord::Session.get(ticket_string)  # simulated get_session
    session.save  # simulated save_session

  end

end
