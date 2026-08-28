# Life Business Suit

**Contexto do Projeto:**
Este é um projeto pessoal pertencente ao perfil **moablive**. 

Por favor, ao interagir com esta base de código, tenha em mente que todas as alterações e configurações estão ligadas às preferências e necessidades pessoais deste perfil.

## Branches dos submódulos

A suíte é **mista de propósito** — nada foi renomeado para uniformizar. Antes de
commitar dentro de um submódulo, confira em qual branch ele vive:

| Submódulo | Branch |
|---|---|
| `LBS_MoneyAPP` | `main` |
| `LBS_NotesAPP` | **`master`** |
| `LBS_NotifyAPP` | `main` |
| `LBS_TodoAPP` | `main` |
| `LBS_TTSAPP` | **`master`** |

Esta tabela é a mesma coisa que o campo `branch` de cada seção do `.gitmodules`, e
cada submódulo repete o próprio caso no seu `CLAUDE.md`. Mudou um, mudam os três.

O superprojeto usa **`master`** — é para onde o `origin/HEAD` do
`moablive/LifeBusinessSuit` aponta no GitHub. Houve uma renomeação local para
`main` em 27/08/2026 que empurrou o trabalho para um `origin/main` novo e deixou
o `master` — o branch que todo `git clone` recebe — três commits atrás. Desfeito
em 28/08/2026: nada aqui deve ser renomeado para casar com os apps que usam
`main`, a suíte é mista de propósito.

```bash
git config -f .gitmodules --get-regexp 'submodule\..*\.branch'   # confere a tabela
git submodule foreach 'git branch --show-current'                # confere o disco
```
