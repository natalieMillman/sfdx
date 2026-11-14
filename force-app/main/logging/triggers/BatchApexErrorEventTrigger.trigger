trigger BatchApexErrorEventTrigger on BatchApexErrorEvent(after insert) {
  AsyncFailureHandler.handleBatchErrors(Trigger.new);
}
