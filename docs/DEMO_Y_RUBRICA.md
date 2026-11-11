# Demo, rúbrica y defensa técnica

Guion para presentar el proyecto y evidencia para cada criterio de la rúbrica.

---

## 1. Antes de presentar (5 minutos)

```bash
cd "/ruta/a/22-torre-de-control-tij"
rm -rf _build data
rebar3 compile
rebar3 eunit          # deben ser 33 tests, 0 failures
rebar3 shell
```

Abrir **http://localhost:8080** y dejar el tablero visible. Ten a mano:

- `README.md` (bitácora y arquitectura).
- `docs/GUIA_USO.md` (manual).
- `design/capturas/` (capturas reales).
- `test/` (pruebas).

Si la demo es en WSL, ejecuta `rebar3 shell` **dentro de WSL**.

---

## 2. Guion de demo (10–12 minutos)

### 2.1 Problema y alcance (1 min)

“TIJ tiene una sola pista y decenas de vuelos simultáneos. El problema no es
pintar tarjetas: es mantener **un estado consistente por vuelo**, aceptar solo
transiciones legales, resolver mensajes contradictorios o fuera de orden,
propagar demoras por aeronave y reconstruir todo si un proceso o la VM se caen.
El tablero debe soportar cientos de clientes.”

### 2.2 Arquitectura (2 min)

Mostrar el árbol del README:

```
p22_torre_de_control_tij_sup (rest_for_one)
├── p22_respaldo     ETS + persistent_term + archivo
├── p22_eventos      bus + suscripciones WebSocket
├── p22_puertas      asignador de 20 puertas
├── p22_vuelos_sup   supervisor dinámico
│   └── p22_vuelo_statem × N
├── p22_feed         simulación, caos, niebla, cascada
└── p22_web          cowboy: API, tablero, WS, métricas
```

Frase clave: **un proceso por vuelo**. Así una transición ilegal se rechaza en
el `gen_statem`, la caída de un vuelo no afecta a los demás y el caos es
significativo.

### 2.3 Pruebas (1 min)

```bash
rebar3 eunit
```

Resultado esperado:

```
33 tests, 0 failures
```

Mencionar que cubren ciclo completo, transiciones ilegales, dedupe, autoridad
de fuentes, puertas, cascada, caos, reinicio, API real y el cambio de puerta +
hora.

### 2.4 Tablero y simulación (2 min)

1. En el panel **Simulación**, mostrar el perfil activo (**Lento** por defecto).
2. Cambiar a **Muy lento** y pulsar **Aplicar ritmo**: los tiempos se actualizan
   sin reiniciar.
3. Crear un vuelo con destino `CDMX` y **“entra en 90 s”**: la tarjeta muestra
   la etiqueta `entra en N s`.
4. Pulsar **Pausar** y **Reanudar** para demostrar que no se duplican los ticks.
5. Abrir una tarjeta y pulsar **Abordar**: se asigna una puerta.
6. Mostrar el badge `🚪 puerta_N`.

### 2.5 Caso difícil: puerta + hora a la vez (2 min)

Con el vuelo en **Abordando**:

1. En el modal, fila **Cambiar puerta**, escribir `puerta_5` y `15` minutos.
2. Pulsar **Aplicar**.

Mostrar en pantalla:

- la puerta cambió a `puerta_5`;
- la hora estimada se corrió 15 minutos;
- el badge `⏱ +15 min`;
- la bitácora registra `cambio de puerta a puerta_5 (+15 min)`;
- el estado sigue **Abordando** (no se perdió el abordaje).

Explicar la atomicidad: **primero se toma la nueva puerta y solo después se
libera la vieja**. Si la nueva está ocupada, el vuelo conserva la anterior.

Prueba negativa: intentar moverlo a la puerta de otro vuelo.

```bash
curl -i -X POST localhost:8080/api/vuelos/1/estado \
  -H 'content-type: application/json' \
  -d '{"accion":"cambiar_puerta","fuente":"torre","puerta":"puerta_2","minutos":5}'
```

Esperado: **409** con `vuelo_ocupante`.

### 2.6 Mensajes fuera de orden y fuentes (1 min)

Pulsar **Fuera de orden**. La bitácora muestra `secuencia_repetida`; el estado
no cambia. Explicar:

- cada evento trae `{fuente, seq}`;
- se guarda la última secuencia **por fuente**;
- `torre` (3) prevalece sobre `aerolinea` (2) y `sistema` (1).

### 2.7 Niebla y cascada (1 min)

Pulsar **Niebla +20**: todos los programados pasan a `demorado` con +20 min.
Cancelar un vuelo y mostrar que se cancela el siguiente vuelo de la misma
aeronave (efecto cascada).

### 2.8 Caos (1 min)

Pulsar **Caos**. En el log de la consola debe aparecer **una** reconstrucción:

```
vuelo N en estado ...
```

El vuelo conserva estado, puerta y demora; el tablero no parpadea. Explicar que
el respaldo se escribe **antes** de publicar el evento.

### 2.9 Reinicio de la VM (1 min)

```bash
# En otra terminal, identificar el PID del puerto y matarlo
ss -ltnp | grep 8080
kill -9 <PID>
rebar3 shell
```

Esperado:

```
p22_respaldo foto recuperada de data/p22_respaldo.bin
feed: N vuelos recuperados del respaldo
```

Los vuelos conservan identificación, destino, estado, puerta e historial.

### 2.10 Métricas y cierre (1 min)

Abrir `http://localhost:8080/metrics`:

- `vuelos.por_estado`
- `puertas` libres/ocupadas
- `eventos_por_minuto`
- `clientes_tablero`
- `tipo_cambio_puerta`
- `sistema` con `recon` (procesos, memoria, top 5)

Cerrar con limitaciones reales: la prueba de 300 clientes es local (no red
real/TLS), el ZIP de Stitch ya está en `design/stitch/` y los estados reales se
agrupan en 6.

---

## 3. Mapeo de la rúbrica

| Criterio (12.5 % c/u) | Evidencia en el proyecto | Nivel buscado |
|---|---|---|
| **Solución funcional en Erlang** | `src/` OTP; `gen_statem` por vuelo; 33 pruebas; casos difíciles cubiertos; demo §2. | Excelente |
| **Montaje y ejecución en VM** | `docs/VM_Y_DESPLIEGUE.md`; WSL2/Ubuntu OTP 27; release en Linux; systemd incluido. | Excelente |
| **Demostración del proyecto** | Este guion §2, con comandos y resultados esperados. | Excelente |
| **Diseño UIX con Google Stitch** | ZIP real en `design/stitch/` con las tres pantallas, su HTML y `DESIGN.md`; app alineada a sus tokens/estructura y capturas reales en `design/capturas/`. | Excelente |
| **Manual de uso en Gist** | Publicado: <https://gist.github.com/CarlosEliab/da48ed12e3fbec9f22077040b8227f8d>. | Excelente |
| **Calidad técnica del código** | Módulos separados, `warnings_as_errors`, comentarios de decisiones, pruebas por caso, manejo de errores. | Excelente |
| **Integración backend–entorno–UIX** | API + WebSocket + tablero verificados en vivo; `resync`; capturas; release. | Excelente |
| **Presentación y argumentación** | Guion §2 + preguntas §4 + bitácora del README. | Excelente |

> Sé honesto en la presentación: Stitch y el Gist ya están entregados; lo único
> que puede quedar pendiente es la instalación de systemd en la VM final. El
> resto está implementado y verificado.

---

## 4. Preguntas probables y respuestas

**¿Por qué un proceso por vuelo y no un mapa global?**
Porque el ciclo de vida es independiente y concurrente. Un `gen_statem` por
vuelo aísla las reglas, permite rechazar transiciones ilegales en el origen y
hace que la caída de un vuelo no tumbe el tablero. El supervisor dinámico lo
reconstruye con su último estado.

**¿Por qué `rest_for_one`?**
El orden expresa dependencias: vuelos necesitan respaldo, bus y puertas; la web
necesita el bus. Si cae el respaldo, se reinicia lo que depende de él; si solo
cae la web, los vuelos siguen intactos.

**¿Cómo resuelven mensajes fuera de orden y fuentes contradictorias?**
Cada evento lleva `{fuente, seq}`. Se guarda la última `seq` por fuente y se
descarta `Seq =< última`. La autoridad es `torre(3) > aerolinea(2) >
sistema(1)`; un cambio de menor autoridad se rechaza con
`autoridad_insuficiente`.

**¿Cómo garantizan que no se pierde el estado si matan el proceso?**
Antes de publicar el evento, `p22_respaldo:guardar_vuelo/3` escribe en ETS y
`persistent_term`. Con `persistir=true` también se escribe a
`data/p22_respaldo.bin`. Al reconstruir, `init/1` mezcla el estado guardado.

**¿Qué pasa si se corta la escritura del archivo?**
La foto no es atómica; si queda corrupta, se detecta, se registra y se arranca
limpio. La mejora pendiente es escribir a `.tmp` y renombrar.

**¿Cómo es atómico el cambio de puerta?**
Se valida y se toma la puerta nueva primero (`insert_new` en ETS). Solo si se
obtiene, se libera la anterior. Si la nueva está ocupada, se devuelve error y
el vuelo conserva su puerta y su estado.

**¿Por qué el cambio de puerta no cambia de estado?**
Porque el vuelo sigue en el mismo punto operativo (por ejemplo, abordando); lo
que cambió es el recurso y la hora. La hora se acumula en `demora_min` y se
recalcula `hora_estimada`.

**¿Soporta 300 clientes?**
Sí, medido en esta VM: **300/300 conexiones, 0 fallos, 300 `resync` y 24 600
mensajes en 20 s**; handshake p95 de 97.6 ms y 58.8 MB de memoria en caliente.
El bus serializa **una vez** por evento y hace broadcast; monitorea a cada
suscriptor y lo limpia al morir. La prueba es en loopback local; no se probó a
través de Internet, proxy o TLS. Detalle en `docs/CARGA_300.md`.

**¿Qué fue lo más difícil?**
Los bugs de recuperación: `merge_guardado/3` devolvía solo datos y provocaba un
bucle de reinicios; el dedupe no persistía; el caos llamaba `exit(Id, kill)` con
un entero; `binary_to_term(..., [safe])` rechazaba átomos creados en runtime.
Todo está en la bitácora §5 del README.

**¿Qué mejorarían?**
Modelar la pista como recurso, escritura atómica del respaldo, prueba de carga
de 300 clientes, estados intermedios reales (check-in, última llamada) y
autenticación si se expone fuera de la red interna.

---

## 5. Cierre

El proyecto cumple el objetivo funcional y los casos difíciles del enunciado.
El ZIP de Stitch y el Gist del manual ya están publicados; el equipo es
individual. Solo queda instalar systemd en la VM final si se requiere el
servicio permanente.
