/**
 * Flow action for fault paths. Connect a fault connector to "Log Flow Error"
 * and pass the flow's API name and {!$Flow.FaultMessage}.
 */
public without sharing class LogFlowErrorAction {
  public class Request {
    @InvocableVariable(
      label='Flow API Name'
      description='API name of the flow that failed.'
      required=true
    )
    public String flowApiName;

    @InvocableVariable(
      label='Fault Message'
      description='Pass {!$Flow.FaultMessage}.'
    )
    public String faultMessage;

    @InvocableVariable(
      label='Record Id'
      description='The record the flow was working on, if any.'
    )
    public String recordId;

    @InvocableVariable(
      label='Feature'
      description='Optional feature or business process name.'
    )
    public String feature;
  }

  @InvocableMethod(
    label='Log Flow Error'
    description='Logs a flow failure from a fault path so that it is recorded and can raise a Slack alert.'
    category='Logging'
  )
  public static void log(List<Request> requests) {
    for (Request request : requests) {
      Logger.Entry entry = new Logger.Entry();
      entry.sourceType = Logger.SOURCE_FLOW;
      entry.sourceName = request.flowApiName;
      entry.exceptionType = 'FlowFault';
      entry.message = String.isBlank(request.faultMessage)
        ? 'The flow took a fault path'
        : request.faultMessage;
      entry.recordId = request.recordId;
      entry.feature = request.feature;
      Logger.add(entry);
    }
    Logger.flush();
  }
}
