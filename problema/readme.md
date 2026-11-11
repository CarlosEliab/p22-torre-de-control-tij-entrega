# #22 — Torre de control TIJ: el problema

## Contexto
El Aeropuerto Internacional de Tijuana (TIJ, ICAO MMTJ) opera con una sola pista, pegada a la frontera con Estados Unidos, y es uno de los aeropuertos mas activos del pais con un flujo de pasajeros de varios millones al año. Su terminal conecta por el puente Cross Border Xpress con San Diego, lo que lo hace unico. Los vuelos cambian de estado todo el tiempo y muchas personas (pasajeros, aerolineas, personal en tierra) necesitan ver el mismo estado.

## Datos del mundo real
- Estados tipicos de un vuelo: programado, check-in abierto, abordando, ultima llamada, puerta cerrada, rodando, despego, en vuelo, aterrizado, demorado, cancelado.
- Un vuelo tiene hora programada (STD/STA), estimada (ETD/ETA) y real (ATD/ATA); las diferencias definen demoras.
- Datos de vuelos reales se publican en tableros FIDS; existen APIs publicas (por ejemplo, OpenSky Network, AviationStack) y los horarios de la pagina del aeropuerto.
- Las causas de demora son diversas: clima (niebla costera en la mañana), llegada tardia de la aeronave previa (efecto cascada: ~la mitad de las demoras iniciales vienen de aeronaves que llegaron tarde), pista, trafico aereo, seguridad.
- Con una sola pista, cada despegue y aterrizaje requiere separacion de tiempo y la pista es el recurso mas critico.

## El problema
Mantener, para decenas de vuelos simultaneos, un estado consistente que avanza solo con transiciones validas (no se puede "abordar" despues de "despegar"), propagar las demoras a vuelos posteriores que usan la misma aeronave, y publicar cambios en tiempo real a cientos de pantallas y usuarios.

## Escenario a simular
- 120 vuelos al dia, picos de 10 movimientos por hora, 300 clientes viendo el tablero.
- Niebla que retrasa 20 minutos todas las salidas de la mañana.
- Un vuelo que cambia de puerta y de hora a la vez.

## Casos dificiles
- Mensajes de estado fuera de orden desde fuentes distintas.
- Vuelo cancelado: ¿que pasa con el de regreso de la misma aeronave?
- Reinicio del sistema: reconstruir el estado de cada vuelo.

## Preguntas guia
1. ¿Que transiciones de estado son legales y quien las valida?
2. ¿Que fuente prevalece cuando dos reportan datos contradictorios?

## Que debes entregar (sin que aqui se de la solucion)
- Un diseño OTP explicado brevemente: procesos, supervisores y quien reinicia a quien, justificando cada decision frente a los casos dificiles de arriba.
- La simulacion del escenario descrito, con datos generados y fallas inyectadas.
- Una lista de supuestos propios y de las cifras de este documento que verificaste.
- Una prueba de caos: que mataste, que esperabas y que ocurrio.
- `rebar3 compile` y `rebar3 eunit` en verde; capturas de Stitch y de la app real si hay interfaz.

---
*Las cifras son de referencia (ordenes de magnitud). Verifica la fuente vigente antes de citarlas en tu entrega y anota las que uses en tu README.*
