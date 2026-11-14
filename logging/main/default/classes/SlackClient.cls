/**
 * Posts messages to Slack through the Slack named credential, which adds the
 * bot token. Never throws: the caller gets a Result either way.
 */
public with sharing class SlackClient {
  private static final String ENDPOINT = 'callout:Slack/api/chat.postMessage';
  private static final Integer TIMEOUT_MS = 10000;

  public class Result {
    public Boolean ok = false;
    public String error;
  }

  public static Result post(String channel, String text) {
    Result result = new Result();
    if (String.isBlank(channel)) {
      result.error = 'No Slack channel configured';
      return result;
    }
    HttpRequest request = new HttpRequest();
    request.setEndpoint(ENDPOINT);
    request.setMethod('POST');
    request.setTimeout(TIMEOUT_MS);
    request.setHeader('Content-Type', 'application/json; charset=utf-8');
    request.setBody(
      JSON.serialize(
        new Map<String, Object>{
          'channel' => channel,
          'text' => text,
          'unfurl_links' => false,
          'unfurl_media' => false
        }
      )
    );
    try {
      HttpResponse response = new Http().send(request);
      if (response.getStatusCode() != 200) {
        result.error = 'HTTP ' + response.getStatusCode();
        return result;
      }
      // Slack answers 200 even when it rejects the message.
      Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
        response.getBody()
      );
      result.ok = body.get('ok') == true;
      if (!result.ok) {
        result.error = 'Slack error: ' + String.valueOf(body.get('error'));
      }
    } catch (Exception e) {
      result.ok = false;
      result.error = e.getTypeName() + ': ' + e.getMessage();
    }
    return result;
  }
}
