## Fluxo Git por tarefa — regra básica

Para cada tarefa, crie uma branch dedicada a partir da `main` atualizada. Faça todos os commits relacionados nela e abra apenas um PR para `main`. Atualizações posteriores devem usar a mesma branch e o mesmo PR. Antes da integração, rode `mac-gate npm run preflight:ci` e confirme o Vercel Preview verde no SHA mais recente. Push direto para `main` é proibido, inclusive mediante autorização.
