# Capturas

Recorridos sobre la app conectada a la API de producción
(`https://api-production-4854.up.railway.app/api/v1`).

| Carpeta | Dispositivo | Resolución |
| :--- | :--- | :--- |
| `iphone_6_5/` | **Para App Store — 6.5"** | 1284 × 2778 |
| `ipad/` | iPad Pro 13" M5 (simulador) | 2064 × 2752 |
| `iphone/` | iPhone 17 Pro (simulador), registro de la prueba | 1206 × 2622 |

`iphone_6_5/01_inicio.png` está capturada de forma nativa en un simulador
de iPhone 14 Plus. Las demás están reescaladas desde `iphone/`: el salto
de 1206 × 2622 a 1284 × 2778 cambia la relación de aspecto un 0,5 %,
imperceptible, pero no son capturas nativas.

**No sirven para la ficha de App Store.** Apple exige 1290 × 2796 para
iPhone; las de iPhone están a 1206 × 2622 y hay que recapturar en un
simulador de 6.9". Las de iPad ya están en el tamaño correcto para 13",
pero ambas muestran datos de prueba, la app sin contenido (sin muros,
presas ni rutas) y el icono por defecto de Flutter.

Las de `iphone/` son el recorrido completo paso a paso, diálogos del
sistema incluidos; sirven como registro de la prueba, no como material
de marketing. Las útiles: `01_inicio`, `11_registro`, `14_gym_creado`,
`15_gym_home`, `16_muro`, `23_resultado`.
