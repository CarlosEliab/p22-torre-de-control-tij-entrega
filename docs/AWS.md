# Despliegue en AWS EC2 (Ubuntu)

> **Materia:** Programación Lógica y Funcional  
> **Alumno:** Rodriguez Peraza Carlos Eliab  
> **No. de control:** 23212719  
> **Grupo:** 2-3

Esta guía deja la Torre de control TIJ corriendo en una instancia **AWS EC2 con
Ubuntu 24.04**, accesible por `http://<IP-PUBLICA>:8080`, con arranque automático
y persistencia de vuelos.

**Requisito técnico:** Erlang/OTP **27 o superior**. El proyecto usa el módulo
`json` nativo de OTP 27. Si `apt` instala OTP 25/26, usa `kerl` (se explica
abajo).

---

## 1. Crear la instancia EC2

En la consola de AWS:

1. **EC2 → Launch instance**.
2. Nombre: `p22-torre-tij`.
3. AMI: **Ubuntu Server 24.04 LTS** (64-bit x86).
4. Tipo: `t3.micro` o `t3.small` (2 vCPU / 2 GB es suficiente).
5. Key pair: crea o selecciona una `.pem` (la necesitarás para SSH).
6. Almacenamiento: 10 GB gp3.
7. **Security group**:
   - SSH `22` → *My IP*.
   - HTTP personalizado `8080` → *Anywhere* (`0.0.0.0/0`) para la demo.
8. Launch.

Opcional: asocia una **Elastic IP** para que la dirección no cambie al
detener/iniciar la instancia.

### Conexión

```bash
chmod 400 p22-torre-tij.pem
ssh -i p22-torre-tij.pem ubuntu@<IP-PUBLICA>
```

---

## 2. Instalar Erlang/OTP 27 y rebar3

### 2.1 Intentar con apt

```bash
sudo apt update
sudo apt install -y erlang rebar3
erl -version
```

Si `erl -version` muestra **27 o superior**, salta al paso 3. Si muestra 25 o
26, instala OTP 27 con `kerl`.

### 2.2 Instalar OTP 27 con kerl

```bash
sudo apt update
sudo apt install -y build-essential libssl-dev libncurses-dev \
  libncurses5-dev libssh-dev unixodbc-dev xsltproc fop libxml2-utils

cd /tmp
curl -fsSLO https://raw.githubusercontent.com/kerl/kerl/master/kerl
chmod +x kerl
sudo mv kerl /usr/local/bin/kerl

kerl update releases
kerl list releases | grep '^27' | tail -5
```

Elige la última versión 27 (por ejemplo `27.2.4`) y compila:

```bash
export OTP_VSN=27.2.4          # ajusta al que aparezca en la lista
kerl build "$OTP_VSN" "$OTP_VSN"
sudo mkdir -p /opt/erlang
sudo kerl install "$OTP_VSN" "/opt/erlang/$OTP_VSN"
```

Actívalo para el usuario `ubuntu` y para el servicio:

```bash
echo '. /opt/erlang/'"$OTP_VSN"'/activate' >> ~/.bashrc
. "/opt/erlang/$OTP_VSN/activate"
erl -version
```

> Si la instancia es muy pequeña, la compilación puede tardar 20–40 minutos.
> Ten paciencia o usa una `t3.small` temporalmente.

### 2.3 Instalar rebar3 actual

```bash
curl -fsSL https://github.com/erlang/rebar3/releases/latest/download/rebar3 \
  -o /tmp/rebar3
chmod +x /tmp/rebar3
sudo mv /tmp/rebar3 /usr/local/bin/rebar3
rebar3 version
```

---

## 3. Copiar el proyecto

### Opción A: git clone (recomendada)

```bash
cd ~
git clone https://github.com/CarlosEliab/p22-torre-de-control-tij-entrega.git
cd p22-torre-de-control-tij-entrega
```

### Opción B: paquete `.tar.gz` desde tu computadora

En tu máquina local:

```bash
cd "/ruta/al/22-torre-de-control-tij"
./deploy/empaquetar.sh
```

Sube el paquete y descomprímelo en la VM:

```bash
scp -i p22-torre-tij.pem dist/p22-torre-de-control-tij.tar.gz \
  ubuntu@<IP-PUBLICA>:~/
ssh -i p22-torre-tij.pem ubuntu@<IP-PUBLICA>
tar xzf p22-torre-de-control-tij.tar.gz
cd p22-torre-de-control-tij
```

---

## 4. Compilar y probar

```bash
rebar3 compile
rebar3 eunit
```

Debe terminar con:

```text
33 tests, 0 failures
```

Prueba rápida en primer plano:

```bash
rebar3 shell
```

En otra terminal (o desde tu computadora):

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://<IP-PUBLICA>:8080/
curl -s http://<IP-PUBLICA>:8080/health
curl -s http://<IP-PUBLICA>:8080/api/simulacion
```

Si responde `200`, cierra el shell con `Ctrl+C` dos veces.

---

## 5. Instalar como servicio systemd

El script compila, arma el release, crea el usuario `p22`, copia todo a
`/opt/p22` e instala la unidad de systemd.

```bash
sudo ./deploy/instalar_servicio.sh
```

Verificar:

```bash
systemctl status p22-torre-de-control-tij
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/
curl -s http://127.0.0.1:8080/metrics
```

Logs en vivo:

```bash
journalctl -u p22-torre-de-control-tij -f
```

La aplicación queda en:

| Recurso | Ruta |
|---|---|
| Release | `/opt/p22` |
| Respaldo de vuelos | `/opt/p22/data/p22_respaldo.bin` |
| Servicio | `/etc/systemd/system/p22-torre-de-control-tij.service` |

---

## 6. Abrir el puerto en la VM (si usas ufw)

```bash
sudo ufw allow OpenSSH
sudo ufw allow 8080/tcp
sudo ufw enable
sudo ufw status
```

Recuerda que el **Security Group** de AWS también debe permitir TCP 8080.

---

## 7. Operación diaria

### Arrancar, detener y reiniciar

```bash
sudo systemctl start p22-torre-de-control-tij
sudo systemctl stop p22-torre-de-control-tij
sudo systemctl restart p22-torre-de-control-tij
```

### Cambiar la velocidad de la simulación

Desde el tablero (panel **Simulación**) o por API:

```bash
curl -s -X POST http://127.0.0.1:8080/api/simulacion/ritmo \
  -H 'content-type: application/json' -d '{"perfil":"lento"}'

curl -s -X POST http://127.0.0.1:8080/api/simulacion/ritmo \
  -H 'content-type: application/json' -d '{"nuevo_vuelo_cada_seg":120}'
```

El cambio es en caliente: **no reinicia** el servicio.

### Crear un vuelo con entrada retrasada

```bash
curl -s -X POST http://127.0.0.1:8080/api/vuelos \
  -H 'content-type: application/json' \
  -d '{"destino":"CDMX","aerolinea":"Volaris","entrada_seg":90}'
```

---

## 8. Actualizar la aplicación

```bash
cd ~/p22-torre-de-control-tij-entrega
git pull
sudo ./deploy/instalar_servicio.sh
```

El script conserva `data/` (no borra el respaldo de vuelos).

---

## 9. Respaldo y restauración

### Respaldo

```bash
sudo systemctl stop p22-torre-de-control-tij
sudo tar czf "respaldo-$(date +%F-%H%M).tar.gz" -C /opt/p22 data
sudo systemctl start p22-torre-de-control-tij
```

### Restaurar

```bash
sudo systemctl stop p22-torre-de-control-tij
sudo tar xzf respaldo-AAAA-MM-DD-HHMM.tar.gz -C /opt/p22
sudo chown -R p22:p22 /opt/p22/data
sudo systemctl start p22-torre-de-control-tij
```

También puedes descargar el respaldo a tu computadora:

```bash
scp -i p22-torre-tij.pem \
  ubuntu@<IP-PUBLICA>:/opt/p22/data/p22_respaldo.bin .
```

---

## 10. Cambios de IP o de instancia

- Si usas **Elastic IP**, la dirección se conserva aunque reinicies.
- Si la IP pública cambia, el tablero sigue funcionando; solo cambia la URL:
  `http://<NUEVA-IP>:8080`.
- No es necesario recompilar por un cambio de IP.
- Si cambias de tamaño de instancia, ajusta los schedulers en
  `config/vm.args` (`+S 2:2` para 2 vCPU, `+S 4:4` para 4 vCPU) y vuelve a
  ejecutar el script de instalación.

---

## 11. Solución de problemas

| Síntoma | Causa probable | Solución |
|---|---|---|
| `erl` no existe al usar `sudo` | kerl se activó solo para `ubuntu` | Usa el release (incluye ERTS) o activa OTP también para root |
| `rebar3 compile` falla con `json` | OTP < 27 | Instala OTP 27 con kerl y verifica `erl -version` |
| La página no abre | Security Group o ufw cerrado | Abre TCP 8080 en ambos |
| `502`/conexión rechazada | El servicio no está corriendo | `systemctl status` y `journalctl -u ...` |
| El servicio reinicia en bucle | Ruta o permisos de `data/` | `chown -R p22:p22 /opt/p22/data` |
| `Could not start kernel pid` | `-config` relativo en `vm.args` | Elimínalo: relx ya pasa el `sys.config` correcto |
| La simulación va muy rápido | Perfil `rapido` | Cambia a `lento` desde el tablero o la API |
| Los vuelos no avanzan | `hora_programada` futura | Espera la etiqueta “entra en N s” o usa `entrada_seg` menor |
| El release no arranca en otra arquitectura | Se generó en otro SO/CPU | Genera el release **en la misma VM** donde se ejecutará |

---

## 12. Limpieza (para no gastar crédito)

Cuando termines la demo:

1. Detén la instancia: **EC2 → Instance state → Stop**.
2. Si ya no la necesitas: **Terminate**.
3. Libera la Elastic IP si asociaste una.
4. Revisa **Billing → Cost Explorer** para confirmar que no quedan recursos.
