# Product Requirement Document (PRD) — Boulder Co-Setter App

**Versión:** 1.0.0  
**Estado:** ESPECIFICACIÓN DE PRODUCTO MULTIUSUARIO & CLOUD  
**Enfoque de Desarrollo:** SDD (Software-Driven Development)  
**Infraestructura de Datos:** 100% Centralizada en PostgreSQL  

---

## 1. Visión Global del Producto

### 1.1 Declaración del Problema
El diseño y armado de bloques de escalada (*route setting*) en muros comunitarios, comerciales o domésticos (*Home Walls*, *Spray Walls*) sufre de:
1. **Falta de trazabilidad y autoría:** No hay un registro claro de quién diseñó cada bloque (*route setter*), ni de las evoluciones del muro.
2. **Desconexión entre escaladores:** Los usuarios no pueden explorar, compartir ni calificar rutas creadas por otros setters dentro del mismo muro.
3. **Rigidez en los grados:** Las escalas de dificultad varían según el gimnasio, región o comunidad, requiriendo un sistema de grados parametrizable.
4. **Gestión ineficiente de inventarios:** Las presas físicas no están catalogadas ni asociadas a sus creadores/duenos, lo que dificulta saber qué sets están disponibles para armar.
5. **Deficit de routing:** Al ser un proceso manual, un routing puede demorarse entre 1 y 2 días, además de realizar el routing cada 2 a 3 meses.
6. **No uso de todas las presas y espacio del muro:** Se puede perder espacios del muro y el uso de presas.

### 1.2 Solución
Una plataforma colaborativa multiusuario de **co-creación asistida (Human-in-the-loop)** conectada a un backend centralizado en PostgreSQL. La app permite a los usuarios:
* Registrar los boulder de cada ciudad.
* Registro y autenticación de los routers autorizados por el boulder / *route setter*.
* Registro de sets de las presas con las que cuenta el boulder, clasificandolas por colores.
* Catalogar sets de presas compartidos o privados mediante visión por computador.
* Registrar muros físicos capturando la inclinación exacta vía giroscopio/IMU.
* Diseñar bloques sobre un lienzo 2D interactivo con la ayuda de un motor de IA/reglas biomecánicas.
* Publicar rutas firmadas con su autoría, categorizadas bajo escalas de grado parametrizables (V-Scale, Fontainebleau, etc.).

---

## 2. Objetivos y Métricas de Éxito (KPIs)

* **Trazabilidad de Autoría:** 100% de las rutas registradas quedan vinculadas de forma inmutable al perfil del *route setter* y este esta asociado al boulder.
* **Asociación route setter con boulder:** el *route setter* puede estar vinculado a diferentes boulders.
* **Reusabilidad de Inventario:** Permitir que múltiples setters diseñen rutas sobre un mismo muro utilizando el catálogo central de presas almacenado en PostgreSQL.
* **Tiempo de Catalogación:** Reducir el tiempo de procesamiento y subida a la nube de un set de 10 presas a menos de 15 segundos.
* **Fluidez del Canvas UI:** Mantener 60 FPS estables durante la edición táctil de presas en memoria RAM antes de guardar la ruta en el backend.

---

## 3. Historias de Usuario (User Stories)

* **US-01 (Registro de boulder):** *Como administrador*, quiero crear una cuenta e iniciar par el registro del muro/boulder, teniendo en cuenta nombre, dirección, ciudad, pais, telefono, tarifas y planes.
* **US-02 (Catalogación Cloud de Sets):** *Como usuario administrador*, quiero tomar fotos de mis sets de presas por color para que el sistema las segmentes en el cliente y las suba a la nube guardándolas en mi inventario de PostgreSQL.
* **US-03 (Registro de Muro e Inclinación):** *Como usuario*, quiero registrar mi muro adjuntando su foto y leyendo el ángulo de inclinación con los sensores del teléfono para asociarlo a mi cuenta o dejarlo público.
* **US-04 (Autenticación y Perfil):** *Como escalador/setter*, quiero crear una cuenta e iniciar sesión asociado a un muro.
* **US-05 (Co-Creación y Autoría de Ruta):** *Como route setter*, quiero seleccionar una sección del muro y un grado deseado para que la IA genere una propuesta base que luego pueda modificar en el lienzo 2D, quedando guardada la ruta en la base de datos con mi autoría explícita (`creator_id`).
* **US-06 (Grados Parametrizables):** *Como administrador o setter*, quiero seleccionar el sistema de grados (V-Scale, Font, escala personalizada) bajo el cual se calculará y etiquetará la dificultad de la ruta.
* **US-07 (Exploración de Bloques):** *Como escalador*, quiero consultar el catálogo de rutas guardadas en un muro específico para ver el diseño del bloque, su grado y quién fue el *route setter* que la diseñó.

---

## 4. Requerimientos Funcionales (RF)

### Módulo 1: Gestión de boulder / muro
* **RF-1.1 Registro:** Registro del boulder.
* **RF-1.2 Perfil del boulder:** Almacenamiento de metadatos del boulder (nombre, dirección, ciudad, pais, telefono, tarifas y planes).

### Módulo 2: Gestión de Inventario y Presas (PostgreSQL Backend)
* **RF-2.1 Segmentación en Cliente & Upload:** Detección de presas en RAM vía YOLO-seg/OpenCV y subida inmediata de los PNGs a la nube (S3/Cloud Storage) y PostgreSQL.
* **RF-2.2 Clasificación de Agarre:** Etiquetado de presas: `crimp`, `sloper`, `jug`, `pinch`, `foothold`, `volume`.
* **RF-2.3 Reusabilidad de Sets:** Los sets de presas pueden ser combinados, pero una vez se utilizan se marcan en la base de datos como utilizada, cuando se baja o quita la ruta, las presas vuelven a estado disponible.

### Módulo 3: Configuración de Muros y Sistema de Grados
* **RF-3.1 Registro del Muro:** Almacenamiento de foto del muro, dimensiones físicas ($W \times H$) e inclinación por defecto ($\theta$).
* **RF-3.2 Parametrización de Escalas de Grado:**
  * Soporte para múltiples sistemas de graduación (`V-Scale`, `Fontainebleau`, etc.).
  * Asociación de valores ponderados a cada etiqueta para alimentar el motor de dificultad.

### Módulo 4: Gestión de Usuarios y Autenticación
* **RF-1.1 Registro e Inicio de Sesión:** Autenticación de usuarios vía correo/contraseña o proveedor JWT.
* **RF-1.2 Perfil de Route Setter:** Almacenamiento de metadatos del usuario (nombre de usuario, foto de perfil, rol: escalador / route setter, boulder asociado).

### Módulo 5: Motor de Generación y Editor de Canvas 2D
* **RF-4.1 Selección de Filtros para IA:** El setter elige: Muro, Sistema de Grados, Grado Target, Inclinación de la sesión y Sets Habilitados.
* **RF-4.2 Propuesta y Modificación Manual:** La app pinta la sugerencia en el lienzo 2D y el setter puede arrastrar (*drag*), girar (360°) y reasignar funciones a las presas (`start`, `hand`, `foot_only`, `top`).
* **RF-4.3 Firma de Autoría y Publicación:** Al finalizar el diseño, la ruta se persiste en PostgreSQL con:
  * `wall_id`: Muro donde fue trazada.
  * `creator_id`: ID del usuario/setter que la diseñó.
  * `target_grade_id` / `calculated_grade_id`: Grados dentro del sistema seleccionado.
  * `placed_holds`: Lista de presas con coordenadas relativas $(X\%, Y\%)$, rotación y función.

---

## 5. Requerimientos No Funcionales (RNF)

* **RNF-1 Persistencia Centralizada:** Ninguna información de rutas, muros o inventarios se guarda permanentemente en el almacenamiento local del teléfono. Toda la persistencia reside en PostgreSQL y Object Storage.
* **RNF-2 Rendimiento del Editor:** La manipulación táctil de los objetos sobre el Canvas 2D debe ejecutarse en memoria RAM manteniendo mínimo 60 FPS.
* **RNF-3 Latencia API:** Las consultas a PostgreSQL para cargar el inventario de presas de un muro deben responder en $< 500\text{ ms}$ bajo conexiones móviles 4G/5G.
* **RNF-4 Seguridad de Datos:** Todas las peticiones HTTP al backend deben incluir tokens JWT en los encabezados de autorización.

---

## 6. Fuera de Alcance (Out of Scope para el MVP)

* Transmisión en tiempo real (WebSockets) de múltiples setters editando la misma ruta simultáneamente.
* Generación de modelos o mallas 3D avanzadas. Se trabajará estrictamente sobre Canvas 2D y coordenadas porcentuales sobre la foto del muro.
* Integración con gimnasios comerciales mediante sistemas de cobro / suscripciones de pago.

---

## 7. Matriz Referencial de Grados Parametrizables (Ejemplo)

| System Name | Level Label | Rank Ordinal | Weight Factor |
| :--- | :--- | :--- | :--- |
| **V-Scale** | V0 | 0 | 1.0 |
| **V-Scale** | V4 | 4 | 2.5 |
| **V-Scale** | V8 | 8 | 4.8 |
| **Fontainebleau** | 6A | 4 | 2.5 |
| **Fontainebleau** | 7A | 8 | 4.8 |