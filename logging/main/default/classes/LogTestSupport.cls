/**
 * Shared helpers for the logging tests: a Slack callout mock, custom metadata
 * mocks and direct Log__c inserts.
 */
@IsTest
public class LogTestSupport {
  public static List<HttpRequest> slackRequests = new List<HttpRequest>();

  public class SlackMock implements HttpCalloutMock {
    private final Integer statusCode;
    private final String body;

    public SlackMock(Integer statusCode, String body) {
      this.statusCode = statusCode;
      this.body = body;
    }

    public HttpResponse respond(HttpRequest request) {
      slackRequests.add(request);
      if (statusCode == null) {
        throw new CalloutException('Simulated timeout');
      }
      HttpResponse response = new HttpResponse();
      response.setStatusCode(statusCode);
      response.setBody(body);
      return response;
    }
  }

  public static void slackSucceeds() {
    Test.setMock(HttpCalloutMock.class, new SlackMock(200, '{"ok":true}'));
  }

  public static void slackRejects(String error) {
    Test.setMock(
      HttpCalloutMock.class,
      new SlackMock(200, '{"ok":false,"error":"' + error + '"}')
    );
  }

  public static void slackReturnsStatus(Integer statusCode) {
    Test.setMock(HttpCalloutMock.class, new SlackMock(statusCode, 'error'));
  }

  public static void slackTimesOut() {
    Test.setMock(HttpCalloutMock.class, new SlackMock(null, null));
  }

  /** The text of the nth Slack message sent (0-based). */
  public static String slackText(Integer index) {
    return (String) slackPayload(index).get('text');
  }

  public static String slackChannel(Integer index) {
    return (String) slackPayload(index).get('channel');
  }

  private static Map<String, Object> slackPayload(Integer index) {
    return (Map<String, Object>) JSON.deserializeUntyped(
      slackRequests[index].getBody()
    );
  }

  public static void useSettings(
    String alertChannel,
    String dailyChannel,
    Integer maxAlerts
  ) {
    LogSettings.useMock(
      new Log_Settings__mdt(
        Is_Enabled__c = true,
        Default_Alert_Channel__c = alertChannel,
        Daily_Summary_Channel__c = dailyChannel,
        Retention_Days__c = 30,
        Max_Alerts_Per_Batch__c = maxAlerts
      )
    );
  }

  public static void noAlertRules() {
    LogAlertRules.useMock(new List<Log_Alert_Rule__mdt>());
  }

  public static Log_Alert_Rule__mdt rule(
    String sourceTypes,
    String sourceName,
    Boolean unhandledOnly,
    String channel,
    Integer throttleMinutes
  ) {
    return new Log_Alert_Rule__mdt(
      Source_Types__c = sourceTypes,
      Source_Name__c = sourceName,
      Unhandled_Only__c = unhandledOnly,
      Slack_Channel__c = channel,
      Throttle_Minutes__c = throttleMinutes,
      Is_Active__c = true
    );
  }

  public static Log_Event__e event(
    String sourceType,
    String sourceName,
    String exceptionType,
    String message,
    Boolean isHandled
  ) {
    return new Log_Event__e(
      Level__c = 'ERROR',
      Source_Type__c = sourceType,
      Source_Name__c = sourceName,
      Exception_Type__c = exceptionType,
      Message__c = message,
      Is_Handled__c = isHandled,
      User_Id__c = UserInfo.getUserId(),
      Occurred_At__c = System.now()
    );
  }

  /** Inserts a log row directly, bypassing the event pipeline. */
  public static Log__c insertLog(
    String level,
    String sourceType,
    String sourceName,
    String exceptionType,
    Boolean isHandled,
    Datetime occurredAt
  ) {
    Log__c log = new Log__c(
      Level__c = level,
      Source_Type__c = sourceType,
      Source_Name__c = sourceName,
      Exception_Type__c = exceptionType,
      Message__c = 'Something failed',
      Summary__c = 'Something failed',
      Is_Handled__c = isHandled,
      Occurred_At__c = occurredAt,
      Fingerprint__c = sourceType + sourceName + exceptionType,
      Alert_Status__c = 'None'
    );
    Database.insert(log, AccessLevel.SYSTEM_MODE);
    return log;
  }

  public static List<Log__c> allLogs() {
    return [
      SELECT
        Id,
        Name,
        Level__c,
        Source_Type__c,
        Source_Name__c,
        Exception_Type__c,
        Message__c,
        Summary__c,
        Stack_Trace__c,
        Details__c,
        Feature__c,
        Record_Id__c,
        Is_Handled__c,
        Occurred_At__c,
        Fingerprint__c,
        Alert_Status__c,
        Alert_Channel__c,
        Alert_Error__c,
        Alerted_At__c,
        User__r.Name
      FROM Log__c
      WITH SYSTEM_MODE
      ORDER BY Name
    ];
  }

  public static Log__c onlyLog() {
    List<Log__c> logs = allLogs();
    Assert.areEqual(1, logs.size(), 'Expected exactly one log row');
    return logs[0];
  }
}
