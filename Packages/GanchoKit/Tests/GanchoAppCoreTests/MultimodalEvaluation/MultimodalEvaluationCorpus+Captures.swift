import CoreGraphics
import Foundation

extension MultimodalEvaluationCorpus {
    static let scenes: [(key: String, scene: Scene)] =
        dialogs + diagrams + charts + statusScreens + shapeScenes + notes

    private static let dialogs: [(key: String, scene: Scene)] = [
        (
            "dialog.en.linker",
            .dialog(
                title: "Build Failed",
                message: "The linker could not find symbol swiftRetain in module Core.",
                code: "ERR7301")
        ),
        (
            "dialog.en.payment",
            .dialog(
                title: "Payment Declined", message: "The card issuer rejected this transaction.",
                code: "PAY4410")
        ),
        (
            "dialog.en.disk",
            .dialog(
                title: "Disk Almost Full", message: "Only 2 GB remain on the startup disk.",
                code: "DSK2210")
        ),
        (
            "dialog.en.timeout",
            .dialog(
                title: "Connection Timed Out",
                message: "The server did not respond within 30 seconds.", code: "NET5032")
        ),
        (
            "dialog.en.certificate",
            .dialog(
                title: "Certificate Expired",
                message: "The security certificate for this site expired yesterday.",
                code: "TLS6120")
        ),
        (
            "dialog.en.permission",
            .dialog(
                title: "Permission Denied", message: "This app cannot read the Documents folder.",
                code: "FSY1187")
        ),
        (
            "dialog.en.update",
            .dialog(
                title: "Update Available", message: "Version 4.2 adds offline maps.",
                code: "UPD3305")
        ),
        (
            "dialog.en.sync",
            .dialog(
                title: "Sync Conflict", message: "Two devices edited the same note.",
                code: "SYN8812")
        ),
        (
            "dialog.en.login",
            .dialog(
                title: "Sign-in Failed", message: "Too many attempts. Try again in ten minutes.",
                code: "AUT9021")
        ),
        (
            "dialog.en.battery",
            .dialog(
                title: "Battery Low", message: "Connect the charger to keep working.",
                code: "PWR1450")
        ),
        (
            "dialog.es.compile",
            .dialog(
                title: "Error de compilación", message: "Falta el módulo de red en el proyecto.",
                code: "CMP7302")
        ),
        (
            "dialog.es.payment",
            .dialog(
                title: "Pago rechazado", message: "El banco emisor rechazó esta transacción.",
                code: "PAG4411")
        ),
        (
            "dialog.es.disk",
            .dialog(
                title: "Disco casi lleno", message: "Solo quedan 2 GB en el disco de arranque.",
                code: "DSC2211")
        ),
        (
            "dialog.es.timeout",
            .dialog(
                title: "Tiempo de espera agotado",
                message: "El servidor no respondió en 30 segundos.", code: "RED5033")
        ),
        (
            "dialog.es.certificate",
            .dialog(
                title: "Certificado caducado",
                message: "El certificado de seguridad de este sitio caducó ayer.", code: "TLS6121")
        ),
        (
            "dialog.es.permission",
            .dialog(
                title: "Permiso denegado",
                message: "Esta aplicación no puede leer la carpeta Documentos.", code: "ARC1188")
        ),
        (
            "dialog.es.update",
            .dialog(
                title: "Actualización disponible",
                message: "La versión 4.2 añade mapas sin conexión.", code: "ACT3306")
        ),
        (
            "dialog.es.sync",
            .dialog(
                title: "Conflicto de sincronización",
                message: "Dos dispositivos editaron la misma nota.", code: "SIN8813")
        ),
        (
            "dialog.es.login",
            .dialog(
                title: "Error al iniciar sesión",
                message: "Demasiados intentos. Vuelve a intentarlo en diez minutos.",
                code: "AUT9022")
        ),
        (
            "dialog.es.battery",
            .dialog(
                title: "Batería baja", message: "Conecta el cargador para seguir trabajando.",
                code: "BAT1451")
        )
    ]

    /// Same labels in a different order or without the middle box are the hard
    /// negatives: OCR text alone cannot tell which way the arrows point.
    private static let diagrams: [(key: String, scene: Scene)] = [
        ("diagram.en.queue", .diagram(nodes: ["API", "Queue", "Workers"])),
        ("diagram.en.direct", .diagram(nodes: ["API", "Workers"])),
        ("diagram.en.reversed", .diagram(nodes: ["Workers", "Queue", "API"])),
        ("diagram.en.cache", .diagram(nodes: ["App", "Cache", "Database"])),
        ("diagram.en.cacheReversed", .diagram(nodes: ["Database", "Cache", "App"])),
        ("diagram.en.cdn", .diagram(nodes: ["Browser", "CDN", "Origin"])),
        ("diagram.en.balancer", .diagram(nodes: ["Client", "Load Balancer", "Server"])),
        ("diagram.en.iot", .diagram(nodes: ["Sensor", "Gateway", "Cloud"])),
        ("diagram.en.etl", .diagram(nodes: ["Extract", "Transform", "Load"])),
        ("diagram.en.auth", .diagram(nodes: ["User", "Auth Service", "API"])),
        ("diagram.es.queue", .diagram(nodes: ["API", "Cola", "Procesos"])),
        ("diagram.es.direct", .diagram(nodes: ["API", "Procesos"])),
        ("diagram.es.reversed", .diagram(nodes: ["Procesos", "Cola", "API"])),
        ("diagram.es.cache", .diagram(nodes: ["Aplicación", "Caché", "Base de datos"])),
        ("diagram.es.cacheReversed", .diagram(nodes: ["Base de datos", "Caché", "Aplicación"])),
        ("diagram.es.cdn", .diagram(nodes: ["Navegador", "CDN", "Origen"])),
        ("diagram.es.balancer", .diagram(nodes: ["Cliente", "Balanceador", "Servidor"])),
        ("diagram.es.iot", .diagram(nodes: ["Sensor", "Pasarela", "Nube"])),
        ("diagram.es.etl", .diagram(nodes: ["Extraer", "Transformar", "Cargar"])),
        ("diagram.es.auth", .diagram(nodes: ["Usuario", "Autenticación", "API"]))
    ]

    /// Charts sharing a title differ only in trend, which OCR cannot see.
    private static let charts: [(key: String, scene: Scene)] = {
        let months = ["Jan", "Feb", "Mar", "Apr"]
        let meses = ["Ene", "Feb", "Mar", "Abr"]
        let quarters = ["Q1", "Q2", "Q3", "Q4"]
        let up: [Double] = [2, 4, 6, 8]
        let down: [Double] = [8, 6, 4, 2]
        let flat: [Double] = [5, 5, 5, 5]
        func chart(_ title: String, _ labels: [String], _ values: [Double]) -> Scene {
            .barChart(title: title, labels: labels, values: values)
        }
        return [
            ("chart.en.sales.up", chart("Monthly Sales", months, up)),
            ("chart.en.sales.down", chart("Monthly Sales", months, down)),
            ("chart.en.sales.flat", chart("Monthly Sales", months, flat)),
            ("chart.en.costs.up", chart("Quarterly Costs", quarters, up)),
            ("chart.en.costs.down", chart("Quarterly Costs", quarters, down)),
            ("chart.en.visitors.up", chart("Website Visitors", months, up)),
            ("chart.en.visitors.down", chart("Website Visitors", months, down)),
            ("chart.en.temperature.up", chart("Average Temperature", months, up)),
            ("chart.es.sales.up", chart("Ventas mensuales", meses, up)),
            ("chart.es.sales.down", chart("Ventas mensuales", meses, down)),
            ("chart.es.sales.flat", chart("Ventas mensuales", meses, flat)),
            ("chart.es.costs.up", chart("Costos trimestrales", quarters, up)),
            ("chart.es.costs.down", chart("Costos trimestrales", quarters, down)),
            ("chart.es.visitors.up", chart("Visitas al sitio", meses, up)),
            ("chart.es.visitors.down", chart("Visitas al sitio", meses, down))
        ]
    }()

    private static let statusScreens: [(key: String, scene: Scene)] = {
        func english(_ build: Int, _ passed: Bool, _ production: Bool) -> Scene {
            .statusScreen(
                title: "Deploy Status",
                lines: [
                    "Build \(build)", "Status: \(passed ? "Succeeded" : "Failed")",
                    "Environment: \(production ? "Production" : "Staging")"
                ])
        }
        func spanish(_ build: Int, _ passed: Bool, _ production: Bool) -> Scene {
            .statusScreen(
                title: "Estado del despliegue",
                lines: [
                    "Compilación \(build)", "Estado: \(passed ? "Correcto" : "Fallido")",
                    "Entorno: \(production ? "Producción" : "Pruebas")"
                ])
        }
        return [
            ("status.en.5521.passed", english(5521, true, true)),
            ("status.en.5521.failed", english(5521, false, true)),
            ("status.en.5522.passed", english(5522, true, false)),
            ("status.en.5523.passed", english(5523, true, true)),
            ("status.en.5523.failed", english(5523, false, false)),
            ("status.en.5524.passed", english(5524, true, true)),
            ("status.en.5525.failed", english(5525, false, true)),
            ("status.es.6631.passed", spanish(6631, true, true)),
            ("status.es.6631.failed", spanish(6631, false, true)),
            ("status.es.6632.passed", spanish(6632, true, false)),
            ("status.es.6633.passed", spanish(6633, true, true)),
            ("status.es.6633.failed", spanish(6633, false, false)),
            ("status.es.6634.passed", spanish(6634, true, true)),
            ("status.es.6635.failed", spanish(6635, false, true)),
            ("status.es.6636.passed", spanish(6636, true, false))
        ]
    }()

    private static let shapeScenes: [(key: String, scene: Scene)] = {
        func shape(_ kind: ShapeKind, _ colour: Colour, _ x: Double, _ y: Double) -> Shape {
            Shape(kind: kind, colour: colour, frame: CGRect(x: x, y: y, width: 0.2, height: 0.2))
        }
        return [
            (
                "shapes.redCircleAboveBlueSquare",
                .shapes([
                    shape(.circle, .red, 0.4, 0.15), shape(.square, .blue, 0.4, 0.6)
                ])
            ),
            (
                "shapes.blueSquareAboveRedCircle",
                .shapes([
                    shape(.square, .blue, 0.4, 0.15), shape(.circle, .red, 0.4, 0.6)
                ])
            ),
            (
                "shapes.redCircleBesideBlueSquare",
                .shapes([
                    shape(.circle, .red, 0.2, 0.4), shape(.square, .blue, 0.6, 0.4)
                ])
            ),
            ("shapes.greenTriangle", .shapes([shape(.triangle, .green, 0.4, 0.4)])),
            (
                "shapes.greenAndRedTriangles",
                .shapes([
                    shape(.triangle, .green, 0.2, 0.4), shape(.triangle, .red, 0.6, 0.4)
                ])
            ),
            (
                "shapes.threeYellowCircles",
                .shapes([
                    shape(.circle, .yellow, 0.1, 0.4), shape(.circle, .yellow, 0.4, 0.4),
                    shape(.circle, .yellow, 0.7, 0.4)
                ])
            ),
            ("shapes.oneYellowCircle", .shapes([shape(.circle, .yellow, 0.4, 0.4)])),
            ("shapes.purpleSquare", .shapes([shape(.square, .purple, 0.4, 0.4)])),
            (
                "shapes.twoPurpleSquares",
                .shapes([
                    shape(.square, .purple, 0.2, 0.4), shape(.square, .purple, 0.6, 0.4)
                ])
            ),
            (
                "shapes.orangeTriangleAboveGreenCircle",
                .shapes([
                    shape(.triangle, .orange, 0.4, 0.15), shape(.circle, .green, 0.4, 0.6)
                ])
            ),
            (
                "shapes.greenCircleAboveOrangeTriangle",
                .shapes([
                    shape(.circle, .green, 0.4, 0.15), shape(.triangle, .orange, 0.4, 0.6)
                ])
            ),
            (
                "shapes.fourRedSquares",
                .shapes([
                    shape(.square, .red, 0.2, 0.15), shape(.square, .red, 0.6, 0.15),
                    shape(.square, .red, 0.2, 0.6), shape(.square, .red, 0.6, 0.6)
                ])
            ),
            ("shapes.blueTriangle", .shapes([shape(.triangle, .blue, 0.4, 0.4)])),
            (
                "shapes.yellowSquareBesideBlueCircle",
                .shapes([
                    shape(.square, .yellow, 0.2, 0.4), shape(.circle, .blue, 0.6, 0.4)
                ])
            ),
            ("shapes.redTriangle", .shapes([shape(.triangle, .red, 0.4, 0.4)]))
        ]
    }()

    private static let notes: [(key: String, scene: Scene)] = [
        ("note.en.deploy", .text("Deployment note: run the migration before switching traffic.")),
        ("note.en.velvetRope", .text("Order a velvet rope so guests can queue at the entrance.")),
        ("note.en.groceries", .text("Buy rice, lentils and fresh coriander on Saturday.")),
        ("note.en.meeting", .text("Move the design review to Thursday at three.")),
        ("note.en.recipe", .text("Simmer the tomato sauce for twenty minutes.")),
        ("note.en.trip", .text("Pack hiking boots and a rain jacket for the mountains.")),
        ("note.en.gym", .text("Leg day: squats, lunges and calf raises.")),
        ("note.en.books", .text("Return the borrowed novels to the library on Friday.")),
        (
            "note.es.deploy",
            .text(
                "Nota de despliegue: ejecuta la migración antes de cambiar el tráfico.")
        ),
        ("note.es.bakery", .text("Haz cola en la panadería antes de las ocho.")),
        ("note.es.market", .text("Compra arroz, lentejas y cilantro fresco el sábado.")),
        ("note.es.meeting", .text("Mueve la revisión de diseño al jueves a las tres.")),
        ("note.es.recipe", .text("Cocina la salsa de tomate a fuego lento veinte minutos.")),
        ("note.es.trip", .text("Lleva botas de montaña y un impermeable para la excursión.")),
        ("note.es.books", .text("Devuelve las novelas prestadas a la biblioteca el viernes."))
    ]
}
