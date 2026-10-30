import Foundation

extension MultimodalEvaluationCorpus {
    static let queries: [Query] = english + spanish

    private static func query(
        _ name: String, _ language: String, _ category: Category, heldOut: Bool,
        _ text: String, expecting keys: Set<String> = []
    ) -> Query {
        Query(
            name: name, language: language, category: category, heldOut: heldOut, text: text,
            expectedKeys: keys)
    }

    private static let english: [Query] = [
        query(
            "en.identifier.code", "en", .identifier, heldOut: false, "ERR7301",
            expecting: ["dialog.en.linker"]),
        query(
            "en.identifier.build", "en", .identifier, heldOut: true, "Build 5521 Failed",
            expecting: ["status.en.5521.failed"]),
        query(
            "en.ocr.payment", "en", .ocrParaphrase, heldOut: false,
            "my card was refused at checkout", expecting: ["dialog.en.payment"]),
        query(
            "en.ocr.certificate", "en", .ocrParaphrase, heldOut: false,
            "the website's security certificate is out of date",
            expecting: ["dialog.en.certificate"]),
        query(
            "en.ocr.disk", "en", .ocrParaphrase, heldOut: true,
            "running out of storage space", expecting: ["dialog.en.disk"]),
        query(
            "en.ocr.timeout", "en", .ocrParaphrase, heldOut: true,
            "the remote host never answered", expecting: ["dialog.en.timeout"]),
        query(
            "en.visual.queue", "en", .visualRelation, heldOut: false,
            "architecture diagram with a queue between the API and the workers",
            expecting: ["diagram.en.queue"]),
        query(
            "en.visual.salesDown", "en", .visualRelation, heldOut: false,
            "bar chart where monthly sales fall every month",
            expecting: ["chart.en.sales.down"]),
        query(
            "en.visual.cache", "en", .visualRelation, heldOut: true,
            "diagram where the app reads a cache before the database",
            expecting: ["diagram.en.cache"]),
        query(
            "en.visual.costsUp", "en", .visualRelation, heldOut: true,
            "bar chart where quarterly costs rise every quarter",
            expecting: ["chart.en.costs.up"]),
        query(
            "en.shapes.redAboveBlue", "en", .visualOnly, heldOut: false,
            "a red circle above a blue square",
            expecting: ["shapes.redCircleAboveBlueSquare"]),
        query(
            "en.shapes.threeYellow", "en", .visualOnly, heldOut: true,
            "three yellow circles in a row", expecting: ["shapes.threeYellowCircles"]),
        query(
            "en.none.plumber", "en", .unanswered, heldOut: false,
            "invoice from the plumber in March"),
        query(
            "en.none.lake", "en", .unanswered, heldOut: true,
            "photo of a mountain lake at sunset"),
        query(
            "en.none.wedding", "en", .unanswered, heldOut: true,
            "spreadsheet of wedding guests")
    ]

    private static let spanish: [Query] = [
        query(
            "es.identifier.code", "es", .identifier, heldOut: false, "PAG4411",
            expecting: ["dialog.es.payment"]),
        query(
            "es.identifier.build", "es", .identifier, heldOut: true,
            "Compilación 6633 Fallido", expecting: ["status.es.6633.failed"]),
        query(
            "es.ocr.compile", "es", .ocrParaphrase, heldOut: false,
            "el proyecto no compila porque le falta un módulo",
            expecting: ["dialog.es.compile"]),
        query(
            "es.ocr.certificate", "es", .ocrParaphrase, heldOut: false,
            "el certificado de seguridad del sitio está vencido",
            expecting: ["dialog.es.certificate"]),
        query(
            "es.ocr.disk", "es", .ocrParaphrase, heldOut: true,
            "me estoy quedando sin espacio de almacenamiento", expecting: ["dialog.es.disk"]),
        query(
            "es.ocr.timeout", "es", .ocrParaphrase, heldOut: true,
            "el servidor remoto nunca contestó", expecting: ["dialog.es.timeout"]),
        query(
            "es.visual.queue", "es", .visualRelation, heldOut: false,
            "diagrama con una cola entre la API y los procesos",
            expecting: ["diagram.es.queue"]),
        query(
            "es.visual.salesDown", "es", .visualRelation, heldOut: false,
            "gráfico de barras donde las ventas bajan cada mes",
            expecting: ["chart.es.sales.down"]),
        query(
            "es.visual.cache", "es", .visualRelation, heldOut: true,
            "diagrama donde la aplicación consulta una caché antes de la base de datos",
            expecting: ["diagram.es.cache"]),
        query(
            "es.visual.costsUp", "es", .visualRelation, heldOut: true,
            "gráfico de barras donde los costos suben cada trimestre",
            expecting: ["chart.es.costs.up"]),
        query(
            "es.shapes.greenTriangle", "es", .visualOnly, heldOut: false,
            "un triángulo verde solo", expecting: ["shapes.greenTriangle"]),
        query(
            "es.shapes.fourRed", "es", .visualOnly, heldOut: true,
            "cuatro cuadrados rojos", expecting: ["shapes.fourRedSquares"]),
        query(
            "es.none.plumber", "es", .unanswered, heldOut: false,
            "factura del fontanero de marzo"),
        query(
            "es.none.lake", "es", .unanswered, heldOut: true,
            "foto de un lago de montaña al atardecer"),
        query(
            "es.none.wedding", "es", .unanswered, heldOut: true,
            "hoja de cálculo de invitados a la boda")
    ]
}
