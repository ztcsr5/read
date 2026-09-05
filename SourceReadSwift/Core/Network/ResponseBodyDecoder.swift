import Foundation

/// Decodes the small set of HTTP content codings commonly returned by
/// Android/Legado source hosts.  URLSession usually transparently inflates
/// gzip, but not every iOS transport path does so (and some hosts leave the
/// header behind after an intermediary decoded the body).  The decoder is
/// therefore conservative: a failed or unsupported transform returns the
/// original bytes instead of exposing a partial payload to the rule engine.
struct ResponseBodyDecoder: Sendable {
    struct DecodeResult: Sendable {
        let data: Data
        let encodings: [String]
        let wasDecoded: Bool
    }

    func decode(data: Data, headers: [String: String]) -> Data {
        decodeResult(data: data, headers: headers).data
    }

    func decodeResult(data: Data, headers: [String: String]) -> DecodeResult {
        let value = headers.first { key, _ in
            key.caseInsensitiveCompare("Content-Encoding") == .orderedSame
        }?.value ?? ""
        let encodings = value
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !encodings.isEmpty else {
            return DecodeResult(data: data, encodings: [], wasDecoded: false)
        }

        // Content codings are applied left-to-right and removed in reverse.
        // Decode transactionally so an unsupported outer layer never leaks a
        // partially decoded body into the source parser.
        var candidate = data
        for encoding in encodings.reversed() {
            guard let decoded = decodeOne(candidate, encoding: encoding) else {
                return DecodeResult(data: data, encodings: encodings, wasDecoded: false)
            }
            candidate = decoded
        }
        return DecodeResult(data: candidate, encodings: encodings, wasDecoded: candidate != data)
    }

    /// Applies transport decoding to an already materialized response.  This
    /// is used at the engine boundary as well as by URLSession so injected
    /// fixture clients and WebView/bridge adapters observe identical bytes.
    /// The original body is retained when a custom client has no binary data
    /// to normalize (for example a text-only test double).
    func normalize(_ response: SourceResponse, preferredCharset: String? = nil) -> SourceResponse {
        guard !response.data.isEmpty else { return response }
        let decoded = decodeResult(data: response.data, headers: response.headers)
        let decodedData = decoded.data
        guard decoded.wasDecoded else {
            // Keep the observed coding list even when the payload is already
            // inflated by an intermediary or the coding is unsupported. This
            // gives diagnostics enough transport evidence to distinguish a
            // raw response from a successfully decoded one without exposing a
            // partial transform to source rules.
            guard !decoded.encodings.isEmpty else { return response }
            return SourceResponse(
                url: response.url,
                statusCode: response.statusCode,
                headers: response.headers,
                body: response.body,
                data: response.data,
                encodedByteCount: response.encodedByteCount ?? response.data.count,
                bodyWasDecoded: response.bodyWasDecoded,
                contentEncodings: decoded.encodings
            )
        }
        let body = ResponseTextDecoder().decode(
            data: decodedData,
            headers: response.headers,
            preferredCharset: preferredCharset
        )
        return SourceResponse(
            url: response.url,
            statusCode: response.statusCode,
            headers: response.headers,
            body: body,
            data: decodedData,
            encodedByteCount: response.encodedByteCount ?? response.data.count,
            bodyWasDecoded: true,
            contentEncodings: decoded.encodings
        )
    }

    private func decodeOne(_ data: Data, encoding: String) -> Data? {
        switch encoding {
        case "identity":
            return data
        case "gzip", "x-gzip":
            return gunzip(data)
        case "deflate":
            return inflate(data, rawDeflate: false) ?? inflate(data, rawDeflate: true)
        default:
            // Brotli and vendor codings are intentionally left for a future
            // optional decoder; returning nil preserves the original body.
            return nil
        }
    }

    private func gunzip(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 18,
              bytes[0] == 0x1f, bytes[1] == 0x8b,
              bytes[2] == 8, bytes[3] & 0xe0 == 0 else { return nil }
        var index = 10
        let trailerStart = bytes.count - 8
        let flags = bytes[3]

        if flags & 0x04 != 0 {
            guard index + 2 <= trailerStart else { return nil }
            let length = Int(bytes[index]) | (Int(bytes[index + 1]) << 8)
            index += 2
            guard index + length <= trailerStart else { return nil }
            index += length
        }
        if flags & 0x08 != 0, !skipZeroTerminated(bytes, index: &index, limit: trailerStart) {
            return nil
        }
        if flags & 0x10 != 0, !skipZeroTerminated(bytes, index: &index, limit: trailerStart) {
            return nil
        }
        if flags & 0x02 != 0 {
            guard index + 2 <= trailerStart else { return nil }
            index += 2
        }
        guard index < trailerStart else { return nil }
        return inflate(Data(bytes[index..<trailerStart]), rawDeflate: true)
    }

    private func skipZeroTerminated(_ bytes: [UInt8], index: inout Int, limit: Int) -> Bool {
        while index < limit {
            defer { index += 1 }
            if bytes[index] == 0 { return true }
        }
        return false
    }

    private func inflate(_ data: Data, rawDeflate: Bool) -> Data? {
        guard !data.isEmpty else { return nil }
        var outputPointer: UnsafeMutablePointer<UInt8>?
        var outputLength = 0
        let status = data.withUnsafeBytes { buffer -> Int32 in
            guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return sourceread_zlib_inflate(
                base,
                data.count,
                &outputPointer,
                &outputLength,
                rawDeflate ? 1 : 0
            )
        }
        guard status == 0, let outputPointer else {
            if let outputPointer { sourceread_zlib_free(outputPointer) }
            return nil
        }
        defer { sourceread_zlib_free(outputPointer) }
        return Data(bytes: outputPointer, count: max(0, outputLength))
    }
}
