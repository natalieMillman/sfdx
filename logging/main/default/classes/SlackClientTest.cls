@IsTest
private class SlackClientTest {
  @IsTest
  static void postsChannelAndTextThroughTheNamedCredential() {
    LogTestSupport.slackSucceeds();

    Test.startTest();
    SlackClient.Result result = SlackClient.post('#alerts', 'Hello');
    Test.stopTest();

    Assert.isTrue(result.ok, 'Slack accepted the message');
    Assert.isNull(result.error);
    Assert.areEqual(1, LogTestSupport.slackRequests.size());
    HttpRequest request = LogTestSupport.slackRequests[0];
    Assert.areEqual(
      'callout:Slack/api/chat.postMessage',
      request.getEndpoint()
    );
    Assert.areEqual('POST', request.getMethod());
    Assert.areEqual('#alerts', LogTestSupport.slackChannel(0));
    Assert.areEqual('Hello', LogTestSupport.slackText(0));
  }

  @IsTest
  static void rejectionWithHttp200IsAFailure() {
    LogTestSupport.slackRejects('channel_not_found');

    Test.startTest();
    SlackClient.Result result = SlackClient.post('#missing', 'Hello');
    Test.stopTest();

    Assert.isFalse(result.ok, 'ok:false must count as a failure');
    Assert.areEqual('Slack error: channel_not_found', result.error);
  }

  @IsTest
  static void httpErrorIsAFailure() {
    LogTestSupport.slackReturnsStatus(503);

    Test.startTest();
    SlackClient.Result result = SlackClient.post('#alerts', 'Hello');
    Test.stopTest();

    Assert.isFalse(result.ok);
    Assert.areEqual('HTTP 503', result.error);
  }

  @IsTest
  static void calloutExceptionIsAFailureNotAnException() {
    LogTestSupport.slackTimesOut();

    Test.startTest();
    SlackClient.Result result = SlackClient.post('#alerts', 'Hello');
    Test.stopTest();

    Assert.isFalse(result.ok);
    Assert.isTrue(result.error.contains('Simulated timeout'), result.error);
  }

  @IsTest
  static void blankChannelIsNotSent() {
    LogTestSupport.slackSucceeds();

    Test.startTest();
    SlackClient.Result result = SlackClient.post(' ', 'Hello');
    Test.stopTest();

    Assert.isFalse(result.ok);
    Assert.areEqual('No Slack channel configured', result.error);
    Assert.areEqual(0, LogTestSupport.slackRequests.size());
  }
}
