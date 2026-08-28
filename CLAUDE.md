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

O superprojeto usa `main`.

```bash
git config -f .gitmodules --get-regexp 'submodule\..*\.branch'   # confere a tabela
git submodule foreach 'git branch --show-current'                # confere o disco
```
