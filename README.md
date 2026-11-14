# Salesforce DX Project

Salesforce DX is a development approach that brings source-driven development, team collaboration, and continuous integration to the Salesforce Platform. Instead of working directly in an org through a web browser, you work with metadata as source files in a local DX project, track changes in version control, and deploy through automated processes.

This project template gets you started with the tools and structure you need to build Salesforce applications using source control, scratch orgs, and the Salesforce CLI.

## Prerequisites

Before you start, make sure you have:

- **Salesforce CLI** - Download from [developer.salesforce.com/tools/salesforcecli](https://developer.salesforce.com/tools/salesforcecli). See [Install Salesforce CLI](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_install_cli.htm) for details.
- **VS Code with Salesforce Extension Pack** - See [Installation Instructions](https://developer.salesforce.com/docs/platform/sfvscode-extensions/guide/install.html) for details. Includes the Agentforce Vibes extension.
- **A development org** - Sign up for a free Developer Edition org [here](https://developer.salesforce.com/signup).
- **Dev Hub enabled** (optional, required to create scratch orgs) - You can enable Dev Hub in your development org under Setup > Dev Hub. See [Provide Developers Access to Salesforce DX Tools](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_setup_dx_tools.htm).

## Project Structure

Your DX project follows this structure:

- **`force-app/main/default/`** - Your metadata source files live in this default package directory. You can configure additional package directories in the `sfdx-project.json` file.
- **`config/`** - Scratch org definitions and project settings
- **`scripts/`** - Automation scripts for common tasks
- **`sfdx-project.json`** - Project manifest that defines package directories, namespace, API version, and other project-level settings

See [Salesforce DX Project Configuration](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_ws_config.htm).

## Get Started

Ready to start developing? The [Get Started with Salesforce DX](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_get_started_dx.htm) guide walks you through your first project, from creating a scratch org to creating a simple Apex class or LWC to deploying your code to a sandbox.

## Common Salesforce CLI Commands

Here are common CLI commands that you'll use the most:

- `sf org login web`: Authorize an org
- `sf org open`: Open your org in a browser
- `sf org create scratch`: Create a scratch org
- `sf project deploy start`: Deploy metadata to your org
- `sf project retrieve start`: Retrieve metadata from your org
- `sf template generate <artifact>`: Scaffold new components, such as Apex classes and triggers, LWC components, Lightning apps, and more
- `sf apex <command>`: Run Apex tests, run anonymous Apex blocks, and view logs
- `sf data <command>`: Work with test data
- `sf alias <command>`: Manage org aliases
- `sf config <command>`: Configure CLI settings

## Use Agentforce Vibes to Build Lightning Apps

Transform your ideas into custom Lightning apps that extend CRM workflows directly in Lightning Experience. Through natural conversations with Agentforce Vibes, implement custom objects and fields, complex business logic, and dynamic UI components. See [Build a Lightning App Using Agentforce Vibes](https://developer.salesforce.com/docs/platform/einstein-for-devs/guide/lexapp-overview.html).

## Additional Resources

- [Agentforce Vibes Developer Guide](https://developer.salesforce.com/docs/platform/einstein-for-devs/guide/einstein-overview.html)
- [Salesforce CLI Installation Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_intro.htm)
- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/)
- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/)
- [Salesforce CLI Plugin Development Guide](https://developer.salesforce.com/docs/platform/salesforce-cli-plugin/guide/conceptual-overview.html)
- [Salesforce VS Code Extensions Documentation](https://developer.salesforce.com/tools/vscode/)

## Exception Logging and Slack Alerts

The `logging` package directory is a self-contained logging framework with no dependency on the rest of the project. It is listed before `force-app` in `sfdx-project.json` because the Add-On code calls it. Every logged failure becomes a `Log__c` record (Logs tab), matching failures post to Slack within seconds, and one Slack message each morning tabulates the previous 24 hours.

Logs are published as `Log_Event__e` platform events with the Publish Immediately behavior, so a log is kept even when the transaction that wrote it rolls back.

### Logging from code

| Situation                                                                                   | What to write                                                                                                                                                                                                                                                       |
| ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Caught exception you deal with                                                              | `Logger.error('MyClass.myMethod', e);` The entry is buffered until `Logger.flush()`.                                                                                                                                                                                |
| Apex entry point (trigger handler, `@AuraEnabled`, REST resource, `@future`, `Schedulable`) | Wrap the body: `try { ... } catch (Exception e) { Logger.unhandled('MyClass', e); throw e; } finally { Logger.flush(); }` See `AddOnTriggerHandler`.                                                                                                                |
| Queueable                                                                                   | First line of `execute`: `System.attachFinalizer(new LoggingFinalizer('MyQueueable'));`                                                                                                                                                                             |
| Batch Apex                                                                                  | Add `Database.RaisesPlatformEvents` to the class. Failures are logged by `BatchApexErrorEventTrigger`.                                                                                                                                                              |
| Callout                                                                                     | `Logger.integrationError('BillingApi.createInvoice', request, response);` for a failure response, or pass the caught exception in place of the response. Only the method, endpoint path, status and a response excerpt are logged, never headers or request bodies. |
| Flow                                                                                        | Connect each fault connector to the **Log Flow Error** action. Pass the flow API name and `{!$Flow.FaultMessage}`.                                                                                                                                                  |

For async entry points pass the source type so the right alert rule matches, for example `Logger.unhandled(Logger.SOURCE_SCHEDULABLE, 'NightlyJob', e)`.

`Logger` never throws and works for users with no access to the logging objects. Apex at API version 67.0 runs database operations in user mode by default, so the framework opts into system mode explicitly. Keep that when you change it.

### Real-time alert rules

`Log_Alert_Rule__mdt` records decide what alerts. Only `ERROR` entries alert. Shipped rules:

- **Unhandled Apex**: any unhandled Apex exception.
- **Async Jobs**: any Batch, Queueable, Schedulable or Future failure.
- **Integrations**: any integration failure.

To alert on a flow, add a record with Source Types `Flow` and Source Name set to the flow API name (a trailing `*` matches by prefix). A rule that names a source wins over a general rule. Leave Slack Channel blank to use the default alert channel from `Log_Settings.Default`.

Repeats of one failure in a burst send one alert with a count. A failure that alerted within the rule's Throttle Minutes is not sent again, and at most Max Alerts Per Batch messages go out per batch of events.

### One-time setup

1. **Slack app.** Create a Slack app with the bot scopes `chat:write` and `chat:write.public`, install it to the workspace, and copy the bot token. Create the channels named in `Log_Settings.Default` (or edit that record).
2. **Running user.** Choose the active user the logging pipeline runs as, ideally a dedicated integration user.
3. **Deploy** with that user's username in the environment. The deploy fails without it:

   ```bash
   LOGGING_RUN_AS_USERNAME=integration.user@example.com sf project deploy start --source-dir logging --target-org <alias>
   ```

4. **Permission sets.** Assign **Logging Runtime** to the running user. Give people who read logs **Log Viewer**.
5. **Token.** In Setup, open Named Credentials, then the External Credentials tab, then **Slack**. On the **Bot** principal add an authentication parameter named `BotToken` whose value is the bot token. The token is never stored in source.
6. **Restart the trigger.** In Setup, open Platform Events, then **Log Event**. In the Subscriptions list click **Manage** next to `LogEventTrigger`, then suspend and resume it. Do this after the first deploy and whenever the running user changes. Until you do, the trigger keeps running as the Automated Process user, which cannot use the Slack credential, and every alert fails with "We couldn't access the credential(s)".
7. **Schedule the jobs** as the running user (daily summary at 08:00, purge at 02:00 in that user's time zone):

   ```bash
   sf apex run --file scripts/apex/schedule-logging-jobs.apex --target-org <alias>
   ```

8. **Catch-all for failures nothing else caught.** In Setup, open Email Services, then **ExceptionEmailService**, and add an email address that runs as the running user. Add that address under Apex Exception Email. In Process Automation Settings set "Send Process or Flow Error Email to" to Apex Exception Email Recipients. Once real emails arrive, restrict the address's "Accept Email From" list to the senders you see, so nobody else can inject log entries.

   This catch-all is best effort. The email wording is not a published contract and Salesforce does not send an email for every repeat of an error, so guards and fault paths remain the primary capture.

9. **Check it.** Run `Logger.unhandled('SmokeTest', new IllegalArgumentException('test'));` as anonymous Apex. Within a minute an alert should appear in the alert channel and the new log's Alert Status should be `Sent`. If it is `Failed`, Alert Error says why.

### Operating it

- Post a summary now: `System.enqueueJob(new LogDailySummaryJob.Sender());`
- Turn logging off: clear Is Enabled on `Log_Settings.Default`.
- Retention: logs older than Retention Days are deleted nightly by `LogPurgeBatch`.
- A failed Slack post is recorded on the log (Alert Status `Failed`, Alert Error). Failures of the logging pipeline itself are logged with source type `Logging`, which never alerts, so a broken alert cannot alert about itself.
