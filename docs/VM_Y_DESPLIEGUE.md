# Montaje en VM y despliegue

> **Materia:** Programación Lógica y Funcional  
> **Docente:** René Solís Reyes  
> **Alumno:** Rodriguez Peraza Carlos Eliab  
> **No. Control:** 23212719  
> **Grupo:** 2-3

**Repositorio:** <https://github.com/CarlosEliab/p22-torre-de-control-tij-entrega>

Este documento cubre el criterio **“Montaje y ejecución en máquina virtual”**.
La solución se verificó en **WSL2 con Ubuntu + Erlang/OTP 27**, que es una VM
Linux gestionada por Windows, y también en Windows nativo con OTP 29. El
release se ensambló y se ejecutó en Linux.

---

## 1. Opción A — WSL2 (la usada para verificar)

### Instalar

En PowerShell (como administrador):

```powershell
wsl --install -d Ubuntu
```

Reinicia si lo pide. Luego, dentro de Ubuntu:

```bash
sudo apt update
sudo apt install -y erlang rebar3
erl -version
rebar3 version
```

Resultado de la máquina de verificación:

```
Erlang/OTP 27 [erts-15.2.7.4]
rebar 3.26.0 on Erlang/OTP 27 Erts 15.2.7.4
```

Si `erl -version` da menos de 27, instala con asdf o kerl.

### Proyecto

```bash
cd "/mnt/c/Users/<usuario>/.../22-torre-de-control-tij"
rm -rf _build data
rebar3 compile
rebar3 eunit
rebar3 shell
```

Abrir en Windows: **http://localhost:8080**. WSL2 reenvía el puerto.

> **No mezcles entornos.** Un `_build` generado en WSL (Linux/OTP 27) no sirve
> para el Erlang de Windows, y viceversa. Si cambias, borra `_build/`.
>
> Para más velocidad, copia el proyecto dentro de WSL (`~/p22`) en lugar de
> compilar sobre `/mnt/c` (OneDrive es lento).

### Apagar y liberar el puerto

```bash
ss -ltnp | grep 8080        # muestra el PID
kill <PID>                  # usa el PID exacto, no pkill por nombre
```

---

## 2. Opción B — VM Linux (VirtualBox, VMware, AWS Academy, Corellium)

1. Crea una VM Ubuntu 24.04 o similar, 2 vCPU y 2 GB de RAM.
2. Instala Erlang/OTP 27+ y rebar3 como en la opción A.
3. Copia el proyecto **sin `_build/` ni `data/`**.
4. `rebar3 compile && rebar3 eunit`.
5. `rebar3 shell` y abre `http://<IP-de-la-VM>:8080`.
6. Si hay firewall: `sudo ufw allow 8080/tcp`.

La aplicación escucha en `0.0.0.0:8080` (configurable en `config/sys.config`).

---

## 3. Release (sin necesidad de Erlang instalado)

```bash
rebar3 release
_build/default/rel/p22_torre_de_control_tij/bin/p22_torre_de_control_tij foreground
```

El release incluye ERTS, dependencias y `priv/index.html`. **Genéralo en el
mismo sistema operativo donde se despliega**: relx produce binarios y scripts
de esa plataforma.

Verificado en Linux (WSL2/Ubuntu, OTP 27):

```
Release successfully assembled: _build/default/rel/p22_torre_de_control_tij
GET /            -> 200
GET /api/vuelos  -> 200
GET /metrics     -> 200
```

### Corrección importante en `config/vm.args`

No incluyas `-config sys.config` en `vm.args`. relx ya pasa
`-config <release>/releases/<vsn>/sys.config`; un `-config` relativo hace que
el kernel busque `./sys.config` y aborte con:

```
Could not start kernel pid (application_controller)
("error in config file "./sys.config" (none): configuration file not found")
```

El `vm.args` de este proyecto ya está corregido y añade los argumentos
recomendados por el repositorio del curso:

```
+S 4:4 +SDcpu 4:4 +SDio 10 +K true +P 1048576
```

---

## 4. Servicio systemd

Unidad incluida en
[`deploy/p22-torre-de-control-tij.service`](../deploy/p22-torre-de-control-tij.service).

```bash
sudo useradd --system --home /opt/p22 p22
sudo mkdir -p /opt/p22
sudo chown p22:p22 /opt/p22
sudo cp -r _build/default/rel/p22_torre_de_control_tij/* /opt/p22/
sudo cp deploy/p22-torre-de-control-tij.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now p22-torre-de-control-tij
```

Verificar:

```bash
systemctl status p22-torre-de-control-tij
curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/
journalctl -u p22-torre-de-control-tij -f
```

El respaldo queda en `/opt/p22/data/p22_respaldo.bin`; el usuario `p22` debe
tener escritura ahí. Si usas otra ruta, ajusta `WorkingDirectory` y
`archivo_respaldo` en `config/sys.config`.

> La unidad se incluye como plantilla. En la máquina de verificación se probó
> el **release en foreground** y las rutas; la instalación systemd queda para
> el servidor Linux definitivo (requiere root). Los comandos de arriba son los
> mismos que usa la unidad.

---

## 5. Evidencia de la VM

| Prueba | Resultado |
|---|---|
| `erl -version` en WSL | OTP 27 / ERTS 15.2.7.4 |
| `rebar3 version` | 3.26.0 |
| `rebar3 compile` | OK, sin warnings |
| `rebar3 eunit` | **33 tests, 0 failures** |
| `rebar3 release` | release ensamblado |
| Release en Linux | `/`, `/api/vuelos`, `/metrics` → **200** |
| Persistencia | `data/p22_respaldo.bin`; recuperación tras reinicio |
| WebSocket | conectado; `resync` y eventos en vivo |

---

## 6. Notas para la presentación

- Muestra `uname -a`, `erl -version` y `rebar3 version` al inicio: deja claro
  que corre en una VM Linux definida.
- Enseña el release arrancando sin `rebar3`: demuestra que el entorno queda
  autocontenido.
- Si el profesor pide “VM en la nube”, los mismos pasos aplican a una instancia
  Ubuntu de AWS Academy; solo cambia la IP y el grupo de seguridad (puerto
  8080).
