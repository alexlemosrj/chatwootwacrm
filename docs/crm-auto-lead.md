# CRM auto-lead

Auto-lead is opt-in per account. No deployment date or inactivity window is used.
An administrator/operator can configure the existing Account settings through Rails:

```ruby
account = Account.find(account_id)
account.with_lock { account.update!(crm_auto_lead_enabled: true) }
# To pause processing and prevent new eligible journeys:
account.with_lock { account.update!(crm_auto_lead_enabled: false) }
```

The setting accepts a boolean only. It is disabled when absent. This patch does not
add a settings screen or expose the setting through the public Account API.

## Journey and activation

A small model concern snapshots persisted account activation when a conversation
is created, under the account lock. Only newly created conversations are eligible.
Existing conversations and the bulk historical importer retain the database default
`ineligible`. Enabling or re-enabling never backfills these conversations.

The internal `conversations.crm_auto_lead_state` enum is:

- `ineligible` (0): never armed, including existing/imported conversations.
- `eligible` (1): may convert; no age limit while the journey remains open.
- `processed` (2): an automatic deal was created or an existing manual deal consumed
  the opportunity. Deleting or unlinking the deal cannot reset this state.
- `closed` (3): the conversation was resolved; reopening cannot reset this state.

Resolution persists closure with the status update, not through an asynchronous
reporting listener. A conversation born resolved is immediately closed when opted in.
Disabling pauses processing of already eligible journeys; enabling again can resume
those journeys, but cannot arm conversations born while disabled.

## Conversion

The existing asynchronous `message.created` dispatcher enqueues `Crm::AutoLeadJob`
for public incoming messages on eligible conversations. The job resolves Account,
Conversation and Message with account-scoped real primary keys. It runs
`Crm::CreateAutoLead` under a conversation row lock.

Conversion requires a valid customer incoming A, business outgoing B and triggering
customer incoming C with strictly `A.created_at < B.created_at < C.created_at`.
Equal timestamps do not establish order. Queue execution order is irrelevant.
Only incoming messages whose sender is the conversation's Contact count.

Private, activity, deleted, failed, auto-reply email and call-indicator messages do
not count. Templates (including greeting/away messages) deliberately do not count
as B in this version. Outgoing sender identity is unrestricted: human, automation,
bot and AI can all qualify.

`sent` alone is not evidence of sending because it is the initial message state.
B must be `delivered`/`read`, or `sent` with a nonempty external `source_id` (provider
acceptance/echo). Channels/integrations without these signals will not qualify.
These signals are evaluated when C is processed; the model does not provide a
universal delivery timestamp. Message order refers to Chatwoot's persisted timestamps,
not a reconstruction of the provider's original chronology.

The default account pipeline and its first stage ordered by position/id are used.
Probability and status follow the stage defaults. The deal, a `deal_created` CrmEvent
with `metadata.source = auto_lead`, and the processed state commit together.
Missing pipeline/stages raise a job error and leave the state retryable. No CRM error
rolls back incoming message receipt. A receipt arriving after C's job has completed
does not itself trigger conversion; another incoming message can trigger evaluation.

## Concurrency and scope

Manual deal creation/link changes take the same conversation lock and consume an
eligible journey immediately, in the transaction that saves the deal. Failed saves
or transaction rollbacks leave the journey unchanged. Removing or unlinking the
deal cannot restore eligibility. Ineligible and closed journeys remain unchanged.

A new manual link to a processed journey returns a validation error (HTTP 422),
including when the automatic job wins the lock first. Existing deals can still be
edited. Thus either winner of a manual/automatic race leaves exactly one deal.
The service explicitly marks its deal instance with the internal creation source
`auto_lead` (not accepted by the API); it owns the atomic deal/event/state write.
There is no global or thread-local callback bypass.

The state is internal, not a custom/additional attribute permitted by the API.
Direct SQL/bulk writes that bypass model callbacks must preserve lifecycle invariants;
the historical importer intentionally leaves conversations ineligible.

No historical backfill or Kanban realtime update is included. Reload/reopen the board
to see a background-created deal. Deployments must migrate before enabling accounts.
