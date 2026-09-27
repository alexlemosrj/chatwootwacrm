Fase 1 de integridade CRM — relatório de implementação e validação

Data: 2026-09-26. Branch: `upgrade/chatwoot-4.18-kanban`.
HEAD de origem: `bbcf73078faf03bce6186a59069bc1e2a5d6d604`.
Ambiente: Ruby 3.4.4, Node 24.21.0, `RAILS_ENV=test`, `DISABLE_ENTERPRISE=true`, banco local `chatwoot_test`.

**Causas e comportamento implementado**

| Fluxo | Causa raiz | Resultado |
| --- | --- | --- |
| Conversation → Deal | O JSON CE expõe `display_id` como `id`; o sidebar enviava esse valor como FK interna. Referências opcionais inexistentes escapavam da validação do modelo. | Identificadores explícitos, resolução por Account na API e resposta 422 para referências inválidas. A coluna `deals.conversation_id` recebe exclusivamente `conversations.id`. |
| Exclusão de Conversation | Ausência de associação Rails e FK com NO ACTION impediam o job de concluir. | Rails nullifica o vínculo e o banco usa ON DELETE SET NULL. O job real conclui sem remover Deal, Activity ou Event. O contrato assíncrono CE é preservado. |
| Exclusão de Contact | O Contact desconhecia os vínculos CRM; o bloqueio ocorria somente na FK e virava 500. | `restrict_with_error` para os três vínculos, antes das associações CE. O controller responde 422 com mensagem compreensível. A FK continua impedindo exclusão física. |
| Merge de Contact | O merge CE não transferia Deal, CrmActivity e CrmEvent. | Transferência dos três tipos na transação existente, antes de excluir o incorporado. Apenas `contact_id` muda; metadados e timestamps históricos permanecem. |
| Remoção de Agent | A remoção de AccountUser limpava apenas atribuições CE em job posterior. | Deal e Activity ficam sem assignee imediatamente, na transação da remoção de AccountUser e apenas naquela Account. Outras Accounts mantêm suas atribuições. |
| Exclusão de User/autoria | FKs bloqueavam a exclusão física; a validação de actor exigia associação atual à Account mesmo para eventos históricos. | Atribuições são nullificadas em Rails e no banco. O evento preserva autoria em snapshot, mantendo a FK enquanto o User existir e nullificando-a quando for excluído. |
| Account/Pipeline | Política já corrigida no trabalho anterior. | Exclusão de Account segue a ordem existente. Pipeline com Deal permanece protegido. Cascade Pipeline → PipelineStage preservado. |

**Contrato de identificação**

Fluxo do dashboard: `ContactPanel.conversationId` (display_id CE) → prop `ContactDeals.conversationDisplayId` → `pipelines/createDeal` → `DealsAPI.create({ deal })` → `deal.conversation_display_id` → `Current.account.conversations.find_by(display_id: valor)` → associação Rails `conversation` → FK interna de Deal.

A API também aceita `deal.conversation_id`, que significa exclusivamente PK. Aceita um inteiro JSON positivo ou `null`; rejeita strings, floats, booleanos, arrays, hashes, zero e negativos. Não aceita os dois identificadores juntos, mesmo que um seja null. Omissão mantém o vínculo em updates; null remove o vínculo. Create e update compartilham a validação. O filtro GET `conversation_id` continua usando PK.

Foi escolhida a alternativa explicitamente permitida de `conversation_display_id` porque o dashboard CE já usa display IDs para conversas. Alterar globalmente o significado de `conversation.id` no JSON CE quebraria consumidores existentes. Não há tentativa de adivinhar o significado de um número. Clientes externos devem respeitar o nome do parâmetro; um número enviado como PK é tratado como PK.

**Contact e merge**

Contact com qualquer um dos três tipos de histórico responde 422 à exclusão e mantém todos os registros. O merge valida que ambos os contatos pertencem à Account, transfere as referências CRM e preserva o fluxo CE de Conversations, Messages, ContactInbox e Notes. Não existem restrições únicas por Contact nos três modelos CRM que exijam deduplicação. Se o sobrevivente falhar em validação, a transação reverte transferências CRM, alterações CE e exclusão do incorporado; esse caso tem spec de request retornando 422. O merge não reatribui actor nem altera metadata dos eventos.

**Estratégia de CrmEvent.actor**

`actor_snapshot` é JSONB obrigatório, com default `{}`, contendo somente `id` e `name`. Novos eventos com actor recebem o snapshot na criação. A migration preenche os eventos existentes por join com Users, preservando todos os campos históricos existentes.

Remover o usuário da Account não muda `actor_id` nem o snapshot. A associação à Account é validada ao criar um evento ou alterar seu actor, permitindo que eventos históricos continuem válidos após a saída do autor. Excluir fisicamente o User torna `actor_id` null, mantendo evento, metadata e snapshot. O serializer expõe `actor_snapshot` e retorna o snapshot em `actor` quando o User já não existe; o Funil continua exibindo o nome do autor, em vez de “System”. Nenhum evento é atribuído a outro usuário.

O snapshot de dados legados representa o nome disponível no momento da migration; o de novos eventos representa o nome no momento da criação. Não inclui email, tokens ou credenciais. A migration é deliberadamente irreversível: `down` lança `ActiveRecord::IrreversibleMigration`, pois remover o snapshot poderia apagar a única autoria restante após a exclusão do User.

**Migration e schema**

Nova migration: `db/migrate/20260926120000_harden_crm_lifecycle_references.rb`.

- Executada no banco existente `chatwoot_test` por `bundle exec rails db:migrate`.
- `db:migrate:status` confirmou todas as migrations up, incluindo as de CRM de 20260921010000, 20260922180000 e 20260926120000.
- Schema gerado por Rails, sem edição manual. O schema versionado anterior ainda não continha as tabelas CRM; por isso o dump inclui essas tabelas, índices e constraints anteriores, além desta migration. Rails 7.2 normalizou também a versão do dump, ordem de índices e parênteses SQL.
- O primeiro dump sofreu timeout no parser de triggers porque a variável local DEBUG ativava o lexer Ruby. `env -u DEBUG ... rails db:schema:dump` gerou o schema corretamente e preservou os triggers CE originais.
- Instalação limpa via `db:create db:schema:load` validada em banco descartável separado.
- Migration incremental aplicada sobre schema CRM legado em transação de teste: snapshot preenchido, campos históricos preservados e autoria mantida após exclusão SQL do User. Rollback destrutivo da migration também foi recusado conforme esperado.
- Verificação adicional de toda a cadeia histórica desde banco vazio falhou na migration CE intocada `20231211010807_add_cached_labels_list.rb`, por `uninitialized constant ActsAsTaggableOn::Taggable::Cache`. Isso antecede o CRM. O próprio `lib/tasks/db_enhancements.rake` documenta que a instalação usa schema primeiro, pois executar todas as migrations antigas pode falhar. Nenhuma migration histórica foi modificada para contornar isso.

**FKs efetivas em chatwoot_test**

| Coluna(s) | Destino | ON DELETE |
| --- | --- | --- |
| deals.conversation_id | conversations | SET NULL |
| deals.assignee_id | users | SET NULL |
| crm_activities.assignee_id | users | SET NULL |
| crm_events.actor_id | users | SET NULL |
| deals.contact_id, crm_activities.contact_id, crm_events.contact_id | contacts | NO ACTION |
| deals.pipeline_id | pipelines | NO ACTION |
| deals.pipeline_stage_id | pipeline_stages | NO ACTION |
| crm_activities.deal_id, crm_events.deal_id | deals | NO ACTION |
| pipeline_stages.pipeline_id | pipelines | CASCADE (preservado) |
| pipelines.account_id, deals.account_id, crm_activities.account_id, crm_events.account_id | accounts | CASCADE (preservado) |

Nenhum cascade de Contact, User ou Conversation para histórico CRM foi introduzido. As FKs foram inspecionadas pelo adapter Rails no banco principal de teste, com assertions para as políticas alteradas.

**Validação**

| Grupo | Total | Passed | Failed | Pending |
| --- | ---: | ---: | ---: | ---: |
| Integridade CRM | 38 | 38 | 0 | 0 |
| Baseline CRM | 32 | 32 | 0 | 0 |
| Regressões CE | 409 | 408 | 1 | 0 |
| Total Ruby | 479 | 478 | 1 | 0 |
| Frontend CRM/Pipelines | 3 | 3 | 0 | 0 |
| Total Ruby + frontend | 482 | 481 | 1 | 0 |

A execução final habilitou MFA com três chaves aleatórias geradas somente no ambiente do processo de teste. Nenhuma chave foi gravada no repositório ou em configuração persistente. Os oito exemplos que antes eram pending por falta de MFA passaram na execução final.

Única falha final: `spec/models/conversation_spec.rb:1144`, “correctly tracks waiting_since and creates first response time events”; assertion em :1155 recebeu `3602.0`, esperando `3600 ± 1`. O spec calcula instantes com `5.hours.ago` e `4.hours.ago` em momentos diferentes, intercalados com criação de registros e execução de jobs, sem congelar o relógio. A duração dessa preparação entra no cálculo.

Controle sem alterações CRM: exportação por `git archive HEAD` do HEAD original da mesma branch para `/tmp/crm-phase1-baseline`, sem checkout, mudança de branch ou worktree. Executados `spec/models/conversation_spec.rb:1144` e `:1172` no snapshot original, com banco descartável separado: 2 exemplos, 1 failure; a mesma assertion de :1155 recebeu `3602.0`. A repetição isolada no código alterado também apresentou o mesmo resultado. Isso comprova a falha temporal preexistente no ambiente, sem necessidade de modificar o spec CE para ocultá-la. A segunda falha temporal observada numa rodada anterior não ocorreu na execução final.

Evidências locais: `/tmp/crm-phase1-final-rspec.json`, `/tmp/crm-phase1-final-rspec.log`, `/tmp/crm-phase1-baseline-timing.json`, `/tmp/crm-phase1-baseline-timing.log`, `/tmp/crm-phase1-frontend.log`, `/tmp/crm-phase1-rubocop.log`, `/tmp/crm-phase1-eslint.log`, `/tmp/crm-phase1-prettier.log`, `/tmp/crm-phase1-migrate-status.log`, `/tmp/crm-phase1-fks.log`, `/tmp/crm-phase1-migration-check.log` e `/tmp/crm-phase1-clean.log`. Os comandos e resultados essenciais estão registrados neste relatório; logs temporários não foram adicionados ao Git.


Os 19 specs anteriores de integridade foram atualizados para o comportamento correto. A cobertura agora inclui os quatro grupos pedidos, referências inválidas, colisão display_id/PK, exclusão real via job, exclusão SQL direta, rollback de merge e snapshot após mudança de nome/exclusão do autor. O teste frontend monta ContactDeals com o store Pipelines real e verifica o payload entregue à API para display ID numérico, string de rota e ausência de conversa.

Comando Ruby da validação combinada, após inicializar rbenv, com `RAILS_ENV=test DISABLE_ENTERPRISE=true POSTGRES_DATABASE=chatwoot_test`:

```sh
bundle exec rspec \
  spec/requests/crm \
  spec/models/deal_spec.rb spec/models/crm_activity_spec.rb spec/models/pipeline_spec.rb \
  spec/services/crm/provision_account_spec.rb \
  spec/controllers/api/v1/accounts/deals_controller_spec.rb \
  spec/controllers/api/v1/accounts/crm_activities_controller_spec.rb \
  spec/controllers/api/v1/accounts/pipelines_controller_spec.rb \
  spec/jobs/delete_object_job_spec.rb \
  spec/models/contact_spec.rb spec/models/user_spec.rb spec/models/account_user_spec.rb \
  spec/models/conversation_spec.rb spec/actions/contact_merge_action_spec.rb \
  spec/controllers/api/v1/accounts/contacts_controller_spec.rb \
  spec/controllers/api/v1/accounts/agents_controller_spec.rb \
  spec/controllers/api/v1/accounts/conversations_controller_spec.rb \
  spec/controllers/api/v1/accounts/actions/contact_merges_controller_spec.rb \
  spec/controllers/platform/api/v1/users_controller_spec.rb \
  spec/jobs/agents/destroy_job_spec.rb
```

RuboCop em modo check em todos os 15 arquivos Ruby/Jbuilder alterados: zero offenses. Após a proteção de rollback, a migration também foi checada novamente: zero offenses.

ESLint nos três arquivos frontend alterados: zero erros e dois avisos preexistentes em ContactDeals (separador textual e chave dinâmica de tradução). Prettier `--check`: passou. Nenhum `--write` ou autofix foi usado. Vitest executado por `pnpm test app/javascript/dashboard/routes/dashboard/conversation/specs/ContactDeals.spec.js`.

**Arquivos alterados**

- `app/actions/contact_merge_action.rb`
- `app/controllers/api/v1/accounts/contacts_controller.rb`
- `app/controllers/api/v1/accounts/deals_controller.rb`
- `app/javascript/dashboard/routes/dashboard/conversation/ContactDeals.vue`
- `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue`
- `app/javascript/dashboard/routes/dashboard/conversation/specs/ContactDeals.spec.js`
- `app/models/account_user.rb`
- `app/models/concerns/crm/contact_extensions.rb`
- `app/models/contact.rb`
- `app/models/conversation.rb`
- `app/models/crm_event.rb`
- `app/models/user.rb`
- `app/views/api/v1/models/_crm_event.json.jbuilder`
- `config/locales/en.yml`
- `db/migrate/20260926120000_harden_crm_lifecycle_references.rb`
- `db/schema.rb`
- `spec/requests/crm/account_pipeline_integrity_spec.rb`
- `spec/requests/crm/agent_integrity_spec.rb`
- `spec/requests/crm/contact_integrity_spec.rb`
- `spec/requests/crm/conversation_integrity_spec.rb`
- `docs/CRM_PHASE1_INTEGRITY_REPORT.md`

**Revisão e limites**

Diff revisado para alterações acidentais, secrets, debug e arquivos temporários. Nenhuma alteração em main, nenhuma nova branch, merge, rebase, push, deploy ou acesso a VPS/produção. Os specs anteriores estavam sem versionamento e por isso aparecem como arquivos novos no diff. Arquivos novos foram marcados com intenção de adicionar (`git add -N`) apenas para tornar a revisão completa; isso não cria commit.

As extensões Enterprise relacionadas foram inspecionadas; o hook de merge de Calls permanece intacto. A execução foi em CE, sem afirmar validação de toda a suíte Enterprise. Associações comerciais antigas que já tenham sido gravadas com uma PK errada não podem ser reconstruídas por heurística e não foram remapeadas automaticamente. A API/job de exclusão de Conversation mantém o processamento assíncrono CE; o teste executa o job real e confirma que o bloqueio por FK CRM foi removido.

A operação de backfill atualiza os snapshots existentes e a troca de FKs adquire locks de DDL; a validação foi local, não constitui medição de duração em uma base de produção. Nenhum histórico comercial existente fora das fixtures de teste foi apagado. Rollback deve preservar a coluna de snapshot, conforme a proteção da migration.

**Estado Git e conclusão**

Nenhum commit criado, pois a validação completa ainda contém um teste CE vermelho. HEAD final permanece `bbcf73078faf03bce6186a59069bc1e2a5d6d604`, na branch solicitada. `git diff --check` passou. Sem push, merge, rebase ou deploy.

FASE 1 BLOQUEADA — implementação e validação CRM concluídas, mas a regra de entrega exige ausência de testes relevantes vermelhos. O bloqueio é a falha temporal CE preexistente comprovada no HEAD original. Não foi iniciada a próxima fase.

<!-- diff-stat-start -->
```text
 app/actions/contact_merge_action.rb                |  10 ++
 .../api/v1/accounts/contacts_controller.rb         |   2 +
 .../api/v1/accounts/deals_controller.rb            |  35 +++-
 .../routes/dashboard/conversation/ContactDeals.vue |   6 +-
 .../routes/dashboard/conversation/ContactPanel.vue |   2 +-
 .../conversation/specs/ContactDeals.spec.js        |  53 ++++++
 app/models/account_user.rb                         |   9 +-
 app/models/concerns/crm/contact_extensions.rb      |  11 ++
 app/models/contact.rb                              |   4 +-
 app/models/conversation.rb                         |   1 +
 app/models/crm_event.rb                            |   9 ++
 app/models/user.rb                                 |   3 +
 app/views/api/v1/models/_crm_event.json.jbuilder   |   3 +
 config/locales/en.yml                              |   2 +
 ...260926120000_harden_crm_lifecycle_references.rb |  28 ++++
 db/schema.rb                                       | 131 ++++++++++++++-
 docs/CRM_PHASE1_INTEGRITY_REPORT.md                | 178 +++++++++++++++++++++
 .../crm/account_pipeline_integrity_spec.rb         |  51 ++++++
 spec/requests/crm/agent_integrity_spec.rb          | 117 ++++++++++++++
 spec/requests/crm/contact_integrity_spec.rb        |  80 +++++++++
 spec/requests/crm/conversation_integrity_spec.rb   | 146 +++++++++++++++++
 21 files changed, 867 insertions(+), 14 deletions(-)
```
<!-- diff-stat-end -->
