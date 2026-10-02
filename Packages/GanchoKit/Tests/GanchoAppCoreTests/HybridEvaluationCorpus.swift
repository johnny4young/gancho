import Foundation
import GanchoKit

/// Fixed synthetic corpus: 60 queries per language, partitioned by topic rather than wording.
enum HybridEvaluationCorpus {
    struct Topic {
        let english: String
        let englishQuery: String
        let spanish: String
        let spanishQuery: String
    }
    enum Category: String { case literal, paraphrase, filtered, unanswered }
    struct Query {
        let language: String
        let category: Category
        let heldOut: Bool
        let query: ClipSearchQuery
        let expected: Set<UUID>
    }
    static let topics: [Topic] = [
        .init(
            english: "Remember to buy milk and eggs at the supermarket.",
            englishQuery: "What groceries do I need?",
            spanish: "Recuerda comprar leche y huevos en el supermercado.",
            spanishQuery: "¿Qué alimentos tengo que comprar?"),
        .init(
            english: "The dentist appointment is on Monday morning.",
            englishQuery: "When should I get my teeth checked?",
            spanish: "La cita con el dentista es el lunes por la mañana.",
            spanishQuery: "¿Cuándo me revisan los dientes?"),
        .init(
            english: "Restart the web server after deploying the application.",
            englishQuery: "How do I finish shipping the website?",
            spanish: "Reinicia el servidor web tras desplegar la aplicación.",
            spanishQuery: "¿Cómo termino de publicar el sitio?"),
        .init(
            english: "Bake the bread in a hot oven for thirty minutes.",
            englishQuery: "How long does the loaf need to cook?",
            spanish: "Hornea el pan en un horno caliente durante treinta minutos.",
            spanishQuery: "¿Cuánto tarda en cocinarse la hogaza?"),
        .init(
            english: "The train leaves the station at seven in the evening.",
            englishQuery: "When does the railway journey start?",
            spanish: "El tren sale de la estación a las siete de la tarde.",
            spanishQuery: "¿Cuándo comienza el viaje en ferrocarril?"),
        .init(
            english: "Water the garden plants twice each week.",
            englishQuery: "How often should I irrigate the flowers?",
            spanish: "Riega las plantas del jardín dos veces por semana.",
            spanishQuery: "¿Cada cuánto necesitan agua las flores?"),
        .init(
            english: "Run the unit tests before committing source code.",
            englishQuery: "What validation comes before saving a code revision?",
            spanish: "Ejecuta las pruebas unitarias antes de crear un commit.",
            spanishQuery: "¿Qué validación debo realizar antes de registrar los cambios?"),
        .init(
            english: "Pack sunscreen and a swimsuit for the beach holiday.",
            englishQuery: "What should I bring for swimming by the sea?",
            spanish: "Lleva protector solar y un bañador a las vacaciones de playa.",
            spanishQuery: "¿Qué llevo para nadar junto al mar?"),
        .init(
            english: "Charge the laptop battery before the video meeting.",
            englishQuery: "How should I prepare my computer for the call?",
            spanish: "Carga la batería del portátil antes de la reunión por vídeo.",
            spanishQuery: "¿Cómo preparo mi computadora para la llamada?"),
        .init(
            english: "The library books must be returned next Friday.",
            englishQuery: "When do the borrowed novels go back?",
            spanish: "Devuelve los libros de la biblioteca el próximo viernes.",
            spanishQuery: "¿Cuándo tengo que entregar las novelas prestadas?"),
        .init(
            english: "Store the database backup on an encrypted external drive.",
            englishQuery: "Where can I safely keep a copy of my records?",
            spanish: "Guarda el respaldo de la base de datos en un disco externo cifrado.",
            spanishQuery: "¿Dónde conservo de forma segura una copia de los registros?"),
        .init(
            english: "Take the dog for a walk every morning.",
            englishQuery: "What exercise does my pet need daily?",
            spanish: "Pasea al perro cada mañana.",
            spanishQuery: "¿Qué ejercicio necesita mi mascota todos los días?"),
        .init(
            english: "Use earplugs to protect hearing at a loud concert.",
            englishQuery: "How can I avoid damaging my ears during live music?",
            spanish: "Usa tapones para proteger el oído en un concierto ruidoso.",
            spanishQuery: "¿Cómo evito dañar los oídos al escuchar música en directo?"),
        .init(
            english: "Replace the bicycle tire when its rubber is worn.",
            englishQuery: "What should I repair when my bike wheel loses grip?",
            spanish: "Cambia el neumático de la bicicleta cuando la goma esté gastada.",
            spanishQuery: "¿Qué reparo cuando la rueda de mi bici pierde adherencia?"),
        .init(
            english: "Save the invoice as a PDF for accounting.",
            englishQuery: "How should I preserve the purchase receipt for bookkeeping?",
            spanish: "Guarda la factura como PDF para contabilidad.",
            spanishQuery: "¿Cómo conservo el comprobante de compra para las cuentas?"),
        .init(
            english: "Freeze leftover soup in small containers.",
            englishQuery: "How do I preserve the extra meal for later?",
            spanish: "Congela la sopa sobrante en recipientes pequeños.",
            spanishQuery: "¿Cómo conservo la comida que sobró para otro día?"),
        .init(
            english: "Reserve a quiet hotel room near the airport.",
            englishQuery: "Where should I book lodging before my flight?",
            spanish: "Reserva una habitación tranquila de hotel cerca del aeropuerto.",
            spanishQuery: "¿Dónde reservo alojamiento antes de tomar el vuelo?"),
        .init(
            english: "Change the air conditioner filter each season.",
            englishQuery: "What maintenance keeps the cooling system clean?",
            spanish: "Cambia el filtro del aire acondicionado cada temporada.",
            spanishQuery: "¿Qué mantenimiento mantiene limpio el sistema de refrigeración?"),
        .init(
            english: "Practice piano scales for fifteen minutes daily.",
            englishQuery: "What routine improves my keyboard instrument technique?",
            spanish: "Practica escalas de piano quince minutos al día.",
            spanishQuery: "¿Qué rutina mejora mi técnica con el instrumento de teclado?"),
        .init(
            english: "Keep an emergency flashlight beside spare batteries.",
            englishQuery: "What supplies will provide light during a power failure?",
            spanish: "Mantén una linterna de emergencia junto a pilas de repuesto.",
            spanishQuery: "¿Qué suministros dan luz durante un apagón?")
    ]

    // Negative topics are disjoint across calibration and held-out queries.
    static let unansweredEnglish = [
        "Spectral classification of neutron stars", "History of Babylonian royal dynasties",
        "Deep ocean hydrothermal mineral deposits", "Proof of the Riemann hypothesis",
        "Evolution of dinosaur feathers", "Quantum tunnelling in semiconductor junctions",
        "Archaeology of Mayan ceremonial pyramids", "Antarctic penguin population genetics",
        "Volcanic eruptions on Jupiter's moon Io", "Medieval illuminated manuscript pigments"
    ]
    static let unansweredSpanish = [
        "Clasificación espectral de estrellas de neutrones",
        "Historia de las dinastías reales babilónicas",
        "Depósitos minerales hidrotermales del océano profundo",
        "Demostración de la hipótesis de Riemann",
        "Evolución de las plumas de dinosaurios",
        "Efecto túnel cuántico en uniones semiconductoras",
        "Arqueología de pirámides ceremoniales mayas",
        "Genética de poblaciones de pingüinos antárticos",
        "Erupciones volcánicas en Ío, la luna de Júpiter",
        "Pigmentos de manuscritos medievales iluminados"
    ]

    static func identifier(language: String, index: Int) -> UUID {
        UUID(
            uuid: (
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                UInt8((language == "en" ? 0 : 20) + index + 1)
            ))
    }

    static func queries(boardID: UUID) -> [Query] {
        ["en", "es"].flatMap { language in
            var queries: [Query] = []
            for (index, topic) in topics.enumerated() {
                let id = identifier(language: language, index: index)
                let meaning = language == "en" ? topic.englishQuery : topic.spanishQuery
                queries.append(
                    Query(
                        language: language, category: .literal, heldOut: index >= 10,
                        query: ClipSearchQuery(
                            text: "REF\(language.uppercased())\(index)", mode: .exact),
                        expected: [id]))
                queries.append(
                    Query(
                        language: language, category: .paraphrase, heldOut: index >= 10,
                        query: ClipSearchQuery(text: meaning), expected: [id]))
                if index < 5 || (10..<15).contains(index) {
                    queries.append(
                        Query(
                            language: language, category: .filtered, heldOut: index >= 10,
                            query: ClipSearchQuery(
                                text: meaning, sourceAppBundleID: "evaluation.notes",
                                boardID: index.isMultiple(of: 2) ? boardID : nil,
                                pinnedOnly: !index.isMultiple(of: 2)), expected: [id]))
                }
            }
            let unknown = language == "en" ? unansweredEnglish : unansweredSpanish
            for (index, text) in unknown.enumerated() {
                queries.append(
                    Query(
                        language: language, category: .unanswered,
                        heldOut: index >= 5, query: ClipSearchQuery(text: text), expected: []))
            }
            return queries
        }
    }
}
