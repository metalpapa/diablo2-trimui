# Plan de mejoras

Contexto de retomada: 2026-11-16. La rama activa es `experimental/sdl-3.4`.
El proyecto ya se ejecutó en una TrimUI Smart Pro con CrossMix OS, pero la
estabilidad en sesiones largas no está confirmada. Este plan prioriza evidencia
y progreso seguro antes de optimizar por intuición.

## Prioridad 0: validar memoria en el dispositivo

- Instalar el último binario cross-compilado con `bash /tmp/trimui-test-fps.sh`
  si el script sigue disponible; si no, reconstruirlo según README.
- Confirmar que el binario de la SD es el recién construido, y arrancar una
  sesión nueva desde cero.
- Repetir el recorrido: pueblo -> Campo Pedregoso -> Bosque Oscuro -> Pasaje
  Subterráneo nivel 1 -> salir; usar también el portal a Tristram si la sesión
  sigue estable.
- Al volver a conectar la SD, revisar `d2d.log` y `launcher.log`: máximos de
  `rss` y `memavail`, eventos `memory low` y `art back`, `MAIN STUCK`, cuadros
  lentos y `Killed`.
- Criterio: sin `Killed`, memoria disponible recuperándose después de liberar
  arte y sin suelo negro en el nivel activo. Anotar tiempo de sesión y ruta.

## Prioridad 1: aislar crecimiento de memoria restante

- El log anterior al caché compartido mostró RSS de 477 a 750 MB y MemAvailable
  de 355 a 73 MB en pocos segundos al volver al Campo Pedregoso. Es evidencia
  de presión, no prueba de que una única función explique todo el crecimiento.
- Si vuelve a ocurrir con el último binario, añadir mediciones acotadas antes y
  después de construir/instalar niveles, activar habitaciones, generar
  monstruos y restaurar DT1. Registrar RSS, MemAvailable y bytes restaurados.
- Evitar logs por frame; limitar el muestreo para no empeorar el rendimiento.
- Criterio: identificar qué fase explica el mayor incremento y reproducirlo en
  una ruta corta antes de cambiar la gestión de memoria.

## Prioridad 2: comprobar el caché DT1 compartido

- Comparar en TrimUI una sesión fría y otra con varios niveles exteriores ya
  visitados. Mantener el mismo recorrido y anotar RSS/MemAvailable.
- Añadir pruebas focalizadas para una ruta compartida, una ruta ausente,
  liberación/restauración de píxeles y el caso en que el nivel activo comparte
  un archivo con niveles lejanos.
- Revisar la lectura concurrente: los niveles se construyen en segundo plano;
  asegurar que el caché no permita doble decodificación ni lecturas inseguras
  del MPQ.
- La referencia de AbyssEngine no aporta un caché reutilizable: no tiene DT1 ni
  niveles en el árbol actual. Su ciclo explícito de crear/destruir escenas sirve
  como principio de propiedad, no como solución de streaming.

## Prioridad 3: liberar estado de niveles completos, solo si hace falta

- No borrar `Level` hasta enumerar y limpiar todos sus punteros y mapas por
  nivel (`World`, `Fight`, `Loot`, `Spawning`, portales, automapa y cliente).
- Mantener nivel actual, pueblo si está referenciado, niveles de otros
  jugadores y destinos de portales activos.
- Aceptar explícitamente las consecuencias de reconstrucción (por ejemplo,
  monstruos regenerados o ítems del suelo perdidos), sin perder guardado,
  progreso de misiones ni estado del personaje.
- Preparar pruebas de ida/vuelta y sanitizadores en una compilación nativa antes
  de habilitar expulsión en el dispositivo.
- No implementar esta prioridad si el caché DT1 mantiene estable la memoria.

## Prioridad 4: control y rendimiento

- Reprobar equipar con A en el pueblo, repetición del hechizo B al atacar con A,
  transiciones del pueblo al campo y bordes de niveles con poca memoria.
- Mantener los cambios de rendimiento en tareas separadas de estabilidad.
  Usar el protocolo A/B del README (mismo lugar, lluvia y paneles, varios
  minutos) para widescreen, paneles, blits y `-mcpu=cortex_a53`.
- Dar prioridad a medir el crecimiento de memoria y los congelamientos antes de
  retomar optimizaciones de fps.

## Referencia externa revisada

[AbyssEngine](https://github.com/AbyssEngine/AbyssEngine) está incompleto para
este objetivo: el README declara que no soporta saves ni multijugador originales;
el árbol visible contiene escenas de intro/menú, sin DT1 ni niveles. Decodifica
DC6 por instancia y destruye objetos al cambiar de escena. Además, su lector MPQ
marca archivos patch y single-unit como TODO. No copiar ni portar código: seguir
usándolo, si acaso, como referencia ligera de ciclo de vida.
