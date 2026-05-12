import Foundation
import SwiftUI

// MARK: - Creative File Category

enum CreativeFileCategory: String, Codable {
    case prose          = "Prose"
    case screenplay     = "Screenplay"
    case design         = "Design"
    case image          = "Image"
    case audio          = "Audio"
    case video          = "Video"
    case document       = "Document"
    case ebook          = "eBook"
    case code           = "Code"
    case spreadsheet    = "Spreadsheet"
    case presentation   = "Presentation"
    case archive        = "Archive"
    case project        = "Project"
    case font           = "Font"
    case subtitle       = "Subtitle"
    case threed         = "3D"
    case unknown        = "File"

    var systemIcon: String {
        switch self {
        case .prose:         return "doc.text"
        case .screenplay:    return "film"
        case .design:        return "paintbrush"
        case .image:         return "photo"
        case .audio:         return "waveform"
        case .video:         return "video"
        case .document:      return "doc.richtext"
        case .ebook:         return "book"
        case .code:          return "chevron.left.forwardslash.chevron.right"
        case .spreadsheet:   return "tablecells"
        case .presentation:  return "rectangle.on.rectangle"
        case .archive:       return "archivebox"
        case .project:       return "folder.badge.gearshape"
        case .font:          return "textformat"
        case .subtitle:      return "captions.bubble"
        case .threed:        return "cube"
        case .unknown:       return "doc"
        }
    }

    var accentColor: Color {
        switch self {
        case .prose:         return Brand.accent
        case .screenplay:    return Color(hex: "5A6480")  // dusty slate
        case .design:        return Color(hex: "C0783A")  // warm amber
        case .image:         return Color(hex: "C0783A")
        case .audio:         return Color(hex: "2B8A3E")  // deep green
        case .video:         return Color(hex: "2B8A3E")
        case .document:      return Brand.accent
        case .ebook:         return Color(hex: "8A6E42")  // tan-600
        case .code:          return Color(hex: "8C8A84")  // slate-400
        case .spreadsheet:   return Color(hex: "2B8A3E")
        case .presentation:  return Color(hex: "5A6480")
        case .archive:       return Color(hex: "8C8A84")
        case .project:       return Brand.accentDark
        case .font:          return Color(hex: "8A6E42")
        case .subtitle:      return Color(hex: "8C8A84")
        case .threed:        return Color(hex: "5A6480")
        case .unknown:       return Color(hex: "8C8A84")
        }
    }
}

// MARK: - File Type Info

struct CreativeFileInfo {
    let ext: String            // lowercase extension
    let label: String          // short display label
    let category: CreativeFileCategory
    let appHint: String?       // app that opens this (optional)
}

// MARK: - Registry

enum CreativeFileRegistry {

    // MARK: Lookup

    static func info(for path: String) -> CreativeFileInfo {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return table[ext] ?? CreativeFileInfo(ext: ext, label: ext.isEmpty ? "File" : ext.uppercased(),
                                               category: .unknown, appHint: nil)
    }

    static func category(for path: String) -> CreativeFileCategory {
        info(for: path).category
    }

    // MARK: Full table

    static let table: [String: CreativeFileInfo] = {
        var t: [String: CreativeFileInfo] = [:]

        func add(_ ext: String, _ label: String, _ cat: CreativeFileCategory, _ app: String? = nil) {
            t[ext] = CreativeFileInfo(ext: ext, label: label, category: cat, appHint: app)
        }

        // Plain text / prose
        add("txt",      "Plain Text",          .prose)
        add("rtf",      "Rich Text",           .prose)
        add("md",       "Markdown",            .prose)
        add("markdown", "Markdown",            .prose)
        add("tex",      "LaTeX",               .prose)
        add("cls",      "LaTeX Class",         .code)
        add("sty",      "LaTeX Style",         .code)
        add("fountain", "Fountain",            .screenplay, "Fade In / Highland")
        add("fdx",      "Final Draft",         .screenplay, "Final Draft")
        add("fdr",      "Final Draft",         .screenplay, "Final Draft")
        add("celtx",    "Celtx",               .screenplay, "Celtx")
        add("fadein",   "Fade In",             .screenplay, "Fade In")
        add("scriv",       "Scrivener",           .project,    "Scrivener")
        add("scrivx",      "Scrivener",           .project,    "Scrivener")
        add("sceneboard",  "Scene Board",         .project,    "Scene Board")

        // Document formats
        add("doc",      "Word 97-2003",        .document, "Microsoft Word")
        add("docx",     "Word Document",       .document, "Microsoft Word")
        add("odt",      "OpenDocument Text",   .document, "LibreOffice")
        add("pdf",      "PDF",                 .document)
        add("pdfa",     "PDF/A",               .document)
        add("one",      "OneNote",             .document, "Microsoft OneNote")
        add("onepkg",   "OneNote Package",     .document, "Microsoft OneNote")
        add("gdoc",     "Google Doc",          .document, "Google Docs")
        add("html",     "HTML",                .code)
        add("htm",      "HTML",                .code)
        add("xhtml",    "XHTML",               .code)
        add("xml",      "XML",                 .code)
        add("docbook",  "DocBook",             .code)
        add("opf",      "EPUB Source",         .ebook)
        add("ncx",      "EPUB Nav",            .ebook)

        // eBook
        add("epub",     "EPUB",                .ebook)
        add("mobi",     "Mobipocket",          .ebook)
        add("azw3",     "Kindle",              .ebook, "Kindle")

        // Desktop publishing
        add("indd",     "InDesign",            .design, "Adobe InDesign")
        add("idml",     "InDesign Interchange",.design, "Adobe InDesign")
        add("qxp",      "QuarkXPress",         .design, "QuarkXPress")

        // Images
        add("jpg",      "JPEG",                .image)
        add("jpeg",     "JPEG",                .image)
        add("png",      "PNG",                 .image)
        add("tiff",     "TIFF",                .image)
        add("tif",      "TIFF",                .image)
        add("psd",      "Photoshop",           .design, "Adobe Photoshop")
        add("ai",       "Illustrator",         .design, "Adobe Illustrator")
        add("svg",      "SVG",                 .design)
        add("eps",      "EPS",                 .design)
        add("heic",     "HEIC",                .image)
        add("webp",     "WebP",                .image)
        add("gif",      "GIF",                 .image)

        // Audio
        add("wav",      "WAV Audio",           .audio)
        add("mp3",      "MP3",                 .audio)
        add("aiff",     "AIFF",                .audio)
        add("aif",      "AIFF",                .audio)
        add("m4a",      "AAC Audio",           .audio)
        add("flac",     "FLAC",                .audio)
        add("ogg",      "Ogg Audio",           .audio)
        add("als",      "Ableton Live",        .project, "Ableton Live")
        add("flp",      "FL Studio",           .project, "FL Studio")

        // Video
        add("mp4",      "MP4 Video",           .video)
        add("mov",      "QuickTime",           .video)
        add("avi",      "AVI",                 .video)
        add("mkv",      "MKV",                 .video)
        add("m4v",      "iTunes Video",        .video)
        add("prproj",   "Premiere Pro",        .project, "Adobe Premiere Pro")
        add("aep",      "After Effects",       .project, "Adobe After Effects")

        // Subtitles
        add("srt",      "SRT Subtitles",       .subtitle)
        add("vtt",      "WebVTT",              .subtitle)
        add("ssa",      "SubStation Alpha",    .subtitle)
        add("ass",      "Advanced SSA",        .subtitle)

        // Spreadsheets
        add("xls",      "Excel 97-2003",       .spreadsheet, "Microsoft Excel")
        add("xlsx",      "Excel",              .spreadsheet, "Microsoft Excel")
        add("ods",       "OpenDocument Sheet", .spreadsheet, "LibreOffice")
        add("csv",       "CSV",                .spreadsheet)
        add("tsv",       "TSV",                .spreadsheet)

        // Presentations / storyboards
        add("ppt",      "PowerPoint 97-2003",  .presentation, "Microsoft PowerPoint")
        add("pptx",     "PowerPoint",          .presentation, "Microsoft PowerPoint")
        add("key",      "Keynote",             .presentation, "Keynote")
        add("storyboarder", "Storyboarder",    .presentation, "Storyboarder")

        // Databases
        add("mdb",      "Access Database",     .spreadsheet, "Microsoft Access")
        add("accdb",    "Access Database",     .spreadsheet, "Microsoft Access")
        add("sqlite",   "SQLite DB",           .spreadsheet)
        add("db",       "Database",            .spreadsheet)

        // Project / calendar
        add("ics",      "Calendar",            .project)
        add("mpp",      "MS Project",          .project, "Microsoft Project")

        // 3D / animation
        add("blend",    "Blender",             .threed, "Blender")
        add("fbx",      "FBX",                 .threed)
        add("obj",      "Wavefront OBJ",       .threed)
        add("gltf",     "glTF",                .threed)
        add("glb",      "glTF Binary",         .threed)
        add("max",      "3ds Max",             .threed, "Autodesk 3ds Max")

        // Fonts
        add("ttf",      "TrueType Font",       .font)
        add("otf",      "OpenType Font",       .font)
        add("woff",     "Web Font",            .font)
        add("woff2",    "Web Font 2",          .font)

        // Archives
        add("zip",      "ZIP Archive",         .archive)
        add("rar",      "RAR Archive",         .archive)
        add("7z",       "7-Zip Archive",       .archive)
        add("tar",      "TAR Archive",         .archive)
        add("gz",       "Gzip",                .archive)
        add("bz2",      "Bzip2",               .archive)

        // Code / markup
        add("swift",    "Swift",               .code)
        add("py",       "Python",              .code)
        add("js",       "JavaScript",          .code)
        add("ts",       "TypeScript",          .code)
        add("css",      "CSS",                 .code)
        add("json",     "JSON",                .code)
        add("yaml",     "YAML",                .code)
        add("yml",      "YAML",                .code)
        add("toml",     "TOML",                .code)
        add("sh",       "Shell Script",        .code)

        return t
    }()
}
