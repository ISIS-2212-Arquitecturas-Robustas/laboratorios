# Tutorial Github Copilot

GitHub Copilot es un asistente de programación integrado en Visual Studio Code. Puede ayudarte de varias formas: sugiriendo código mientras se escribe, respondiendo preguntas en el chat, planeando tareas antes de implementarlas y ejecutando flujos autónomos mediante agentes. En VS Code, estas capacidades aparecen distribuidas entre sugerencias inline, chat, selección de modelos y modos de trabajo como Ask, Plan y Agent.

##  1. Acceso a la configuración de Copilot

Como parte del [Github Students Developer Pack](https://education.github.com/pack), usted tiene acceso a copilot. Si todavía no ha solicitado acceso puedo hacerlos en el enlace.

Una vez tenga acceso, sincronice su VSCode con su cuenta de **Github** con su correo estudiantil (el que usó para inscribirse al students developer pack)

<img src="./recursos/Pasted image 20260317223324.png" width=500/>
Siga los pasos para terminar de autenticar su cuenta de Github y sea redirigido nuevamente al editor

## 2. Panel de uso y sugerencias inline

Aquí se ve el panel de estado de Copilot en VS Code. Este panel muestra varias cosas importantes:

- **Copilot Pro Usage**: resumen del uso de tu plan.
- **Inline Suggestions**: sugerencias automáticas dentro del editor.
- **Chat messages**: uso de mensajes en el chat.
- **Premium requests**: consumo de solicitudes premium.

<img src="./recursos/Pasted image 20260317223502.png" width=500/>

Desde este panel puede monitorear el uso de Copilot y ajustar cómo quieres recibir sugerencias. Las solicitudes premium tienen un límite mensual (aproximadamente 300 peticiones), por lo que debe medir su uso de el agente y debe decidir de forma inteligente que modelo usar, esto se explicará más adelante.
## 3. Vista de Chat

<div style="display: flex; align-items: end;">
    <img src="./recursos/Pasted image 20260317223519.png" width=200/>
    <div style="margin-left: 20px;">
        <p>A su izquierda verá la pestaña <b>CHAT</b> y la sección <b>SESSIONS</b>.
        El chat de Copilot sirve para interactuar en lenguaje natural con el asistente. Aquí puede:
        </p>
        <ul>
            <li>Pedir explicaciones de código</li>
            <li>Solicitar refactorizaciones</li>
            <li>Generar pruebas</li>
            <li>Consultar errores</li>
            <li>Pedir documentación</li>
            <li>Revisar decisiones de diseño</li>
        </ul>
    </div>
</div>
<br/>
La sección **Sessions** permite organizar conversaciones por tarea o contexto. En la práctica, cada sesión funciona como un hilo de trabajo separado que NO comparten el contexto.

## 5. Selección de modelos
Copilot ofrece varios modelos de lenguaje para diferentes propósitos. En la configuración, puedes elegir entre:
- **Auto:** Copilot selecciona el modelo más adecuado según la tarea. Su consumo será 10% más bajo pero no tendrá el control sobre el modelo
- **Modelos legacy:** Algunos modelos antiguos como GPT-4.1 o GPT-4o no consumen creditos premium (0x) pero tienen capacidades limitadas. Son útiles para tareas simples o cuando está cerca de su límite mensual.
- **Modelos ligeros:** Algunos modelos nuevos con capacidades reducidas como Haiku o los modelos mini de OpenAI consumen menos créditos (entre 0x y 0.33x) y son ideales para tareas que no requieren un entendimiento profundo, como generar código boilerplate, escribir comentarios o realizar refactorizaciones simples.
- **Modelos premium:** Modelos avanzados como GPT-5.3-Codex O Gemini 3.1 Pro ofrecen capacidades superiores para tareas complejas como diseño de arquitectura, generación de código avanzado o resolución de problemas difíciles. Sin embargo, su consumo es mayor (1x), por lo que se recomienda usarlos de forma estratégica.

<img src="./recursos/Pasted image 20260317223603.png" width=300/>

## 6. Modos de trabajo: Agent, Ask y Plan

GitHub Copilot tiene diferentes modos de trabajo.
<img src="./recursos/Pasted image 20260317223615.png" width=300/>

- **Ask:** Este modo es para preguntas directas y respuestas rápidas. Es ideal para consultas específicas sobre código, errores o conceptos. El modelo responde a la pregunta sin ejecutar acciones adicionales.
- **Plan:** En este modo, puede pedirle a Copilot que le ayude a planificar una tarea antes de implementarla. El modelo puede generar un plan de acción detallado, incluyendo pasos a seguir, consideraciones de diseño y posibles soluciones. Es útil para tareas complejas que requieren una estrategia clara antes de escribir código.
- **Agent:** Este modo permite ejecutar flujos de trabajo autónomos mediante agentes. Puede configurar un agente para realizar tareas específicas, como revisar código, generar pruebas o incluso desplegar aplicaciones. El agente puede interactuar con el entorno de desarrollo y tomar decisiones basadas en el contexto. Adicionalmente puede generar código y ejecutar comandos y herramientas.

## 7. Adjuntar contexto al prompt
Con el botón + puede adjuntar archivos, fragmentos de código o incluso URLs para que el modelo tenga más contexto al responder. Esto es especialmente útil para preguntas relacionadas con código específico o para proporcionar información adicional que el modelo pueda necesitar para generar una respuesta precisa.

<img src="./recursos/Pasted image 20260317223626.png" width=400/>

## 8. Comandos rápidos con slash y arroba

En el chat, con el comando **@** puede mencionar archivos o incluso funciones o líneas específicas de código para que el modelo las tenga en cuenta al generar su respuesta. Esto es útil para preguntas relacionadas con código específico o para proporcionar contexto adicional para modificaciones concretas.

Con el comando **/** puede acceder a comandos rápidos para realizar acciones específicas, como generar pruebas, refactorizar código o revisar errores. Estos comandos permiten interactuar de forma más eficiente con el modelo, puede leer la descripción de cada comando para entender su función y aplicarlos según la necesidad.

<img src="./recursos/Pasted image 20260317223715.png" width=400/>