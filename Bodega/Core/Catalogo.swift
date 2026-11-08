import Foundation

// MARK: - Categoría inicial

/// Una categoría inicial de la bodega: nombre visible + emoji representativo.
struct CategoriaSemilla: Hashable {
    let nombre: String
    let emoji: String
}

// MARK: - Catálogo

/// Catálogo de referencia de la app: países, tipos de bebida, categorías iniciales
/// y marcas conocidas.
///
/// Todo es estático y local (la app es 100 % offline). Este catálogo sirve para:
/// - llenar los selectores de país y tipo,
/// - reconocer el país probable a partir del texto de una etiqueta,
/// - sugerir categorías con su emoji,
/// - anotar marcas conocidas para ayudar al reconocimiento.
///
/// Nota: las banderas emoji NO se guardan aquí; se muestran en la interfaz
/// a partir del nombre del país.
enum Catalogo {

    // MARK: - Países

    /// Países de origen que se pueden asignar a un producto.
    /// Solo texto (sin banderas). "Escocia" aparece porque el whisky scotch
    /// tiene su propia lectura comercial, aunque legalmente forma parte del
    /// Reino Unido (ver `paisProbable`).
    static let paises: [String] = [
        "Argentina",
        "Bolivia",
        "Brasil",
        "Chile",
        "Colombia",
        "Costa Rica",
        "República Dominicana",
        "Ecuador",
        "El Salvador",
        "España",
        "Estados Unidos",
        "Francia",
        "Italia",
        "México",
        "Nicaragua",
        "Paraguay",
        "Perú",
        "Portugal",
        "Uruguay",
        "Venezuela",
        "Reino Unido",
        "Escocia",
        "Irlanda",
        "Alemania",
        "Austria",
        "Bélgica",
        "Suiza",
        "Países Bajos",
        "Dinamarca",
        "Suecia",
        "Noruega",
        "Finlandia",
        "Polonia",
        "Letonia",
        "Rusia",
        "Australia",
        "Nueva Zelanda",
        "Japón",
        "China",
        "Corea del Sur",
        "India",
        "Israel",
        "Turquía",
        "Marruecos",
        "Sudáfrica"
    ]

    // MARK: - Tipos de bebida

    /// Tipos de vino (incluye las familias de aperitivo, cóctel, digestivo y vermut).
    static let tiposVino: [String] = [
        "Blanco",
        "Tinto",
        "Rosado",
        "Espumoso",
        "Rosado espumoso",
        "Tinto espumoso",
        "Blanco semidulce",
        "Blanco dulce",
        "Orange",
        "Gris",
        "Sin azúcar",
        "Aperitivo",
        "Cóctel",
        "Digestivo",
        "Vermut"
    ]

    /// Tipos de licor / destilado / aperitivo.
    static let tiposLicor: [String] = [
        "Whisky",
        "Tequila",
        "Ron",
        "Vodka",
        "Gin",
        "Brandy",
        "Aguardiente",
        "Aperitivo",
        "Cóctel",
        "Vermut",
        "Digestivo",
        "Licor de aguardiente",
        "Sake",
        "Mezcal",
        "Calvados",
        "Pisco",
        "Singani",
        "Chinchón",
        "Ron añejo"
    ]

    // MARK: - Categorías iniciales

    /// Categorías que se crean la primera vez que se abre la app.
    static let categoriasIniciales: [CategoriaSemilla] = [
        CategoriaSemilla(nombre: "Vino rosado espumoso", emoji: "🥂"),
        CategoriaSemilla(nombre: "Vino espumoso", emoji: "🫧"),
        CategoriaSemilla(nombre: "Vino blanco", emoji: "🍸"),
        CategoriaSemilla(nombre: "Vino tinto", emoji: "🍷"),
        CategoriaSemilla(nombre: "Vino argentino", emoji: "🇦🇷"),
        CategoriaSemilla(nombre: "Vino español", emoji: "🇪🇸"),
        CategoriaSemilla(nombre: "Vino chileno", emoji: "🇨🇱"),
        CategoriaSemilla(nombre: "Whisky", emoji: "🥃"),
        CategoriaSemilla(nombre: "Tequila", emoji: "🌮"),
        CategoriaSemilla(nombre: "Ron", emoji: "🍹"),
        CategoriaSemilla(nombre: "Vodka", emoji: "🧊"),
        CategoriaSemilla(nombre: "Gin", emoji: "🫗"),
        CategoriaSemilla(nombre: "Aperitivo", emoji: "🍋"),
        CategoriaSemilla(nombre: "Cócteles", emoji: "🍹"),
        CategoriaSemilla(nombre: "Aguardiente", emoji: "🥃"),
        CategoriaSemilla(nombre: "Sake", emoji: "🍶"),
        CategoriaSemilla(nombre: "Vinos y espumantes", emoji: "🍾"),
        CategoriaSemilla(nombre: "Otros", emoji: "📦")
    ]

    // MARK: - Marcas conocidas

    /// Marcas reales de licores, aperitivos, whiskies, vodkas y vinos.
    /// Se usan para sugerir la marca al reconocer una etiqueta y para
    /// completar el campo de marca con un toque.
    /// La lista es abierta: se puede ampliar con más marcas sin tocar nada más.
    static let marcasConocidas: [String] = [
        // Vinos y espumantes
        "Santa Ana", "Santa Julia", "Barolo", "Chandon", "Freixenet",
        "Codorníu", "Gramona", "Torres", "Norton", "Luigi Bosca",
        "Trapiche", "Salton", "Catena Zapata", "Santa Rita",
        // Whiskies
        "Johnnie Walker", "Chivas Regal", "Ballantine's", "Jack Daniel's",
        "Grant's", "Glenfiddich", "Laphroaig", "Oban",
        "Cutty Sark", "The Famous Grouse", "Maker's Mark", "Buffalo Trace",
        "Bulleit", "Sazerac", "Woodford Reserve", "Four Roses",
        // Tequilas y mezcales
        "Herradura", "José Cuervo", "Olmeca", "Olmeca Altesso",
        "Don Julio", "Sierra", "1800", "Reserva de la Familia",
        "Casamino", "Tapatio",
        // Rones
        "Brugal", "Flor de Caña", "Havana Club", "Zacapan", "Diplomático",
        "Cacique", "Caney", "Matusalem",
        // Vodkas y gins
        "Smirnoff", "Absolut", "Belvedere", "Grey Goose", "Cîroc",
        "Finlandia", "Stolichnaya", "Moskovskaya", "Burn",
        "Beefeater", "Tanqueray", "Hendrick's", "Gordon's", "Bombay Sapphire",
        "Plymouth", "Roku", "Citadelle", "Boodles",
        // Brandy, coñac y aguardientes
        "Hennessy", "VSOP", "Don Melchor", "Campari", "Cinzano",
        "Martini", "Cynar", "Fernet Branca", "Fernet", "Ramazzotti",
        "Ischia", "Nardini", "Grappa Nardini", "Averna", "Amaro Montenegro",
        "Disaronno", "Frangelico", "Licor 43", "Chartreuse", "Bénédictine",
        "Grand Marnier", "Cointreau", "Curacao", "Bols",
        // Aperitivos, vermut, digestivos y cócteles
        "Aperol", "Aperol Spritz", "J&B", "Licor de aguardiente", "Hibiscus",
        "Malfy", "Punt e Mes", "San Pellegrino", "Ricard", "Pernod",
        "Southern Comfort", "Baileys", "Malibu", "Kahlua", "Midori",
        "Sambuca", "Vecchia Romagna", "Anisetta Meletti",
        // Otros
        "Jameson", "Napoleón", "Carlos I", "Torres 10"
    ]

    // MARK: - Emoji por tipo

    /// Emoji temático para un tipo de bebida. Si no conoce el tipo devuelve 📦.
    static func emojiParaTipo(_ tipo: String) -> String {
        let clave = Unidades.normaliza(tipo)
        guard !clave.isEmpty else { return emojiPorDefecto }
        if let exacto = emojisPorTipo[clave] { return exacto }
        // Coincidencia parcial: gana el tipo más largo contenido en el texto.
        for candidato in emojisPorTipo.keys.sorted(by: { $0.count > $1.count }) where clave.contains(candidato) {
            return emojisPorTipo[candidato] ?? emojiPorDefecto
        }
        return emojiPorDefecto
    }

    /// Emoji que se usa cuando el tipo no se reconoce.
    static let emojiPorDefecto = "📦"

    /// Tabla tipo → emoji. Las claves van normalizadas (minúsculas, sin acentos).
    private static let emojisPorTipo: [String: String] = [
        // Vinos y espumantes
        "rosado espumoso": "🥂",
        "tinto espumoso": "🥂",
        "blanco espumoso": "🥂",
        "espumoso": "🥂",
        "espumantes": "🥂",
        "blanco semidulce": "🍸",
        "blanco dulce": "🍸",
        "blanco": "🍸",
        "tinto": "🍷",
        "rosado": "🍷",
        "orange": "🍊",
        "gris": "🍷",
        "sin azucar": "🥤",
        // Licores, aperitivos y digestivos
        "whisky": "🥃",
        "whiskey": "🥃",
        "tequila": "🌮",
        "mezcal": "🌵",
        "ron anejo": "🍹",
        "ron": "🍹",
        "vodka": "🧊",
        "gin": "🫗",
        "brandy": "🍷",
        "calvados": "🍏",
        "aguardiente": "🥃",
        "licor de aguardiente": "🥃",
        "pisco": "🥃",
        "singani": "🫗",
        "sake": "🍶",
        "aperitivo": "🍋",
        "coctel": "🍹",
        "vermut": "🍹",
        "digestivo": "☕",
        "chinchon": "🫖"
    ]

    // MARK: - País probable

    /// Regla de detección de país: palabras (normalizadas) → país.
    private struct ReglaPais {
        let pais: String
        let palabras: [String]
    }

    /// Reglas ordenadas: gana la primera que coincide.
    /// Las palabras están normalizadas (minúsculas y sin acentos) porque es el
    /// formato que devuelve `Unidades.normaliza`.
    private static let reglasPais: [ReglaPais] = [
        ReglaPais(pais: "Reino Unido", palabras: ["reino unido", "ingles", "inglesa", "ingleses", "inglesas", "britanico", "britanica", "britanicos", "britanicas", "inglaterra", "escoces", "escocesa", "escoceses", "scotch", "escocia", "scots", "uk", "gb"]),
        ReglaPais(pais: "Corea del Sur", palabras: ["corea del sur", "coreano", "coreana", "coreanos", "coreanas", "corea", "sur de corea"]),
        ReglaPais(pais: "Estados Unidos", palabras: ["estados unidos", "estadounidense", "estadounidenses", "norteamericano", "norteamericana", "norteamericanos", "ee uuu", "usa"]),
        ReglaPais(pais: "República Dominicana", palabras: ["republica dominicana", "dominicano", "dominicana", "dominicanos", "dominicanas"]),
        ReglaPais(pais: "Argentina", palabras: ["argentina", "argentino", "argentinos", "argentinas", "republica argentina"]),
        ReglaPais(pais: "Bolivia", palabras: ["boliviano", "boliviana", "bolivianos", "bolivianas", "bolivia"]),
        ReglaPais(pais: "Brasil", palabras: ["brasileno", "brasilena", "brasilenos", "brasilenas", "brasil", "brazil"]),
        ReglaPais(pais: "Chile", palabras: ["chileno", "chilena", "chilenos", "chilenas", "chile"]),
        ReglaPais(pais: "Colombia", palabras: ["colombiano", "colombiana", "colombianos", "colombianas", "colombia"]),
        ReglaPais(pais: "Costa Rica", palabras: ["costarricense", "costarricenses", "costa rica"]),
        ReglaPais(pais: "Ecuador", palabras: ["ecuatoriano", "ecuatoriana", "ecuatorianos", "ecuatorianas", "ecuador"]),
        ReglaPais(pais: "El Salvador", palabras: ["salvadoreno", "salvadorena", "salvadorenos", "salvadorenas", "el salvador"]),
        ReglaPais(pais: "España", palabras: ["espanol", "espanola", "espanoles", "espanolas", "espana", "spain", "hispano", "hispana", "iberia"]),
        ReglaPais(pais: "Francia", palabras: ["frances", "francesa", "franceses", "francesas", "francais", "francaise", "francaises", "francia", "france"]),
        ReglaPais(pais: "Italia", palabras: ["italiano", "italiana", "italianos", "italianas", "italia", "italy"]),
        ReglaPais(pais: "México", palabras: ["mexicano", "mexicana", "mexicanos", "mexicanas", "mexico"]),
        ReglaPais(pais: "Nicaragua", palabras: ["nicaraguense", "nicaraguenses", "nicaragua"]),
        ReglaPais(pais: "Paraguay", palabras: ["paraguayo", "paraguaya", "paraguayos", "paraguayas", "paraguay"]),
        ReglaPais(pais: "Perú", palabras: ["peruano", "peruana", "peruanos", "peruanas", "peru"]),
        ReglaPais(pais: "Portugal", palabras: ["portugues", "portuguesa", "portugueses", "portuguesas", "portugal"]),
        ReglaPais(pais: "Uruguay", palabras: ["uruguayo", "uruguaya", "uruguayos", "uruguayas", "uruguay"]),
        ReglaPais(pais: "Venezuela", palabras: ["venezolano", "venezolana", "venezolanos", "venezolanas", "venezuela"]),
        ReglaPais(pais: "Irlanda", palabras: ["irlandes", "irlandesa", "irlandeses", "irlandesas", "irlanda"]),
        ReglaPais(pais: "Alemania", palabras: ["aleman", "alemana", "almanes", "alemanas", "alemania", "allemand", "allemande", "allemands", "germany", "deutsche"]),
        ReglaPais(pais: "Austria", palabras: ["austriaco", "austriaca", "austriacos", "austriacas", "austria"]),
        ReglaPais(pais: "Bélgica", palabras: ["belga", "belgas", "belgica"]),
        ReglaPais(pais: "Suiza", palabras: ["suizo", "suiza", "suizos", "suizas"]),
        ReglaPais(pais: "Países Bajos", palabras: ["holandes", "holandesa", "holandeses", "holandesas", "holanda", "paises bajos"]),
        ReglaPais(pais: "Dinamarca", palabras: ["danes", "danesa", "daneses", "danesas", "dinamarca"]),
        ReglaPais(pais: "Suecia", palabras: ["sueco", "sueca", "suecos", "suecas", "suecia"]),
        ReglaPais(pais: "Noruega", palabras: ["noruego", "noruega", "noruegos", "noruegas"]),
        ReglaPais(pais: "Finlandia", palabras: ["finlandes", "finlandia", "finlandeses"]),
        ReglaPais(pais: "Polonia", palabras: ["polaco", "polaca", "polacos", "polacas", "polonia"]),
        ReglaPais(pais: "Letonia", palabras: ["leton", "letona", "letonia"]),
        ReglaPais(pais: "Rusia", palabras: ["ruso", "rusa", "rusos", "rusas", "rusia"]),
        ReglaPais(pais: "Australia", palabras: ["australiano", "australiana", "australianos", "australianas", "australia"]),
        ReglaPais(pais: "Nueva Zelanda", palabras: ["nueva zelanda", "nuevo zelanda", "neozelandes", "neozelandesa", "neozelanda"]),
        ReglaPais(pais: "Japón", palabras: ["japon", "japones", "japonesa", "japoneses", "japonesas", "japan"]),
        ReglaPais(pais: "China", palabras: ["chino", "china", "chinos", "chinas", "chinese"]),
        ReglaPais(pais: "India", palabras: ["indio", "india", "indios", "indias"]),
        ReglaPais(pais: "Israel", palabras: ["israeli", "israel", "israelies"]),
        ReglaPais(pais: "Turquía", palabras: ["turco", "turca", "turcos", "turcas", "turquia"]),
        ReglaPais(pais: "Marruecos", palabras: ["marroqui", "marruecos"]),
        ReglaPais(pais: "Sudáfrica", palabras: ["sudafricano", "sudafricana", "sudafrica", "sudafricas"])
    ]

    /// Intenta deducir el país de origen a partir del texto de una etiqueta.
    /// - Parameter texto: texto libre (normalizado internamente).
    /// - Returns: el nombre del país o `nil` si no se reconoce ninguno.
    static func paisProbable(texto: String) -> String? {
        let normalizado = Unidades.normaliza(texto)
        guard !normalizado.isEmpty else { return nil }
        for regla in reglasPais {
            for palabra in regla.palabras where contiene(palabra: palabra, en: normalizado) {
                return regla.pais
            }
        }
        return nil
    }

    /// True si el país NO es Argentina.
    ///
    /// Decisión: en esta bodega casi todo lo que se maneja es importado.
    /// El usuario pidió que "vino argentino" y "vino español" vivan en secciones
    /// separadas, y que Chile también tenga la suya; por eso lo único que se
    /// considera "local" es Argentina, y Chile, España, Uruguay, etc. quedan
    /// como importados (aunque el usuario los tenga comprados en el país).
    /// Un país vacío (desconocido) NO se marca como importado.
    static func esImportado(pais: String) -> Bool {
        let limpio = pais.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !limpio.isEmpty else { return false }
        return limpio != "argentina"
    }

    /// Comprueba si una palabra (o frase) aparece dentro del texto normalizado.
    ///
    /// - Una sola palabra: tiene que aparecer como palabra completa
    ///   ("chileno" no coincide dentro de "chilenito").
    /// - Varias palabras: la frase tiene que aparecer completa y en orden
    ///   ("corea del sur").
    private static func contiene(palabra: String, en texto: String) -> Bool {
        let piezasTexto = texto.split(separator: " ").map(String.init)
        let piezasBusca = palabra.split(separator: " ").map(String.init)
        guard !piezasTexto.isEmpty, !piezasBusca.isEmpty else { return false }
        if piezasBusca.count == 1 {
            return piezasTexto.contains(piezasBusca[0])
        }
        guard piezasTexto.count >= piezasBusca.count else { return false }
        for inicio in 0...(piezasTexto.count - piezasBusca.count) {
            let ventana = Array(piezasTexto[inicio..<(inicio + piezasBusca.count)])
            if ventana == piezasBusca { return true }
        }
        return false
    }
}
