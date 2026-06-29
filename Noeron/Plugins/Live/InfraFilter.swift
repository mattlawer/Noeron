//
//  InfraFilter.swift
//  Noeron
//
//  Noise control. A lot of DNS/WHOIS/IP data points at shared *infrastructure*
//  (mail providers, CDNs, DNS hosts, registrars, free-webmail backends). Turning
//  those into graph nodes is worse than useless: e.g. expanding "gmail.com" from
//  an email would pull in all of Google's name servers and mail hosts. This filter
//  lets plugins drop such hostnames before they become pivotable nodes.
//

import Foundation

enum InfraFilter {

    /// Registrable suffixes that are provider/CDN/mail/DNS/hosting infrastructure.
    /// Matched as an exact host or a parent suffix (`host == s` or `host.hasSuffix(".s")`).
    static let infraSuffixes: Set<String> = [
        // Google
        "google.com", "googlemail.com", "googleusercontent.com", "googleapis.com",
        "gstatic.com", "1e100.net",
        // Microsoft
        "microsoft.com", "outlook.com", "office365.com", "office.com",
        "microsoftonline.com", "hotmail.com", "live.com", "windows.net",
        // Apple
        "apple.com", "icloud.com", "me.com", "mac.com",
        // Yahoo / Verizon
        "yahoo.com", "yahoodns.net", "ymail.com",
        // Amazon / AWS
        "amazonaws.com", "cloudfront.net", "awsdns-00.org",
        // CDNs
        "cloudflare.com", "cloudflare.net", "akamai.net", "akamaiedge.net",
        "akamaitechnologies.com", "fastly.net", "fastlylb.net",
        // Registrars / managed DNS
        "godaddy.com", "domaincontrol.com", "secureserver.net", "namecheap.com",
        "registrar-servers.com", "dnsimple.com", "nsone.net", "ultradns.com",
        "dynect.net", "dnsmadeeasy.com",
        // Mail providers / gateways
        "sendgrid.net", "mailgun.org", "mandrillapp.com", "sparkpostmail.com",
        "mimecast.com", "pphosted.com", "proofpoint.com", "barracudanetworks.com",
        "messagingengine.com", "kundenserver.de",
        // Other consumer webmail / providers
        "zoho.com", "proton.me", "protonmail.ch", "gmx.net", "gmx.com",
        "fastmail.com", "mail.ru", "yandex.net", "yandex.ru", "qq.com",
        "163.com", "126.com",
        // Hosting / site builders (as CNAME/MX targets these are infra, not the subject)
        "wordpress.com", "wpengine.com", "squarespace.com", "wixdns.net",
        "shopify.com", "herokuapp.com", "netlify.app", "vercel.app", "pages.dev",
        "github.io"
    ]

    /// Vendor tokens whose hostnames vary too much for a fixed suffix
    /// (e.g. `ns-1.awsdns-42.co.uk`). Matched as a substring.
    static let infraTokens: [String] = [
        "awsdns", "azure-dns", "akam", "cloudflare", "fastly",
        "googleusercontent", "1e100", "protection.outlook", "office365",
        "secureserver", "domaincontrol", "registrar-servers", "dynect",
        "ultradns", "nsone", "dnsmadeeasy", "sendgrid", "mimecast",
        "pphosted", "proofpoint", "barracuda"
    ]

    /// True when a hostname is shared infrastructure rather than a meaningful subject.
    static func isInfrastructure(_ host: String) -> Bool {
        let h = host.lowercased().trimmingTrailingDot()
        guard !h.isEmpty else { return true }
        for s in infraSuffixes where h == s || h.hasSuffix("." + s) { return true }
        for t in infraTokens where h.contains(t) { return true }
        return false
    }

    /// Free consumer webmail AND ISP/telco mailbox domains — valid as email
    /// domains, but pointless to expand as infrastructure: you don't want the
    /// WHOIS/subdomains of gmail.com, and you *really* don't want an `@orange.fr`
    /// address to fan the whole Orange ISP out into hundreds of subdomains.
    static let freeWebmail: Set<String> = [
        // Global webmail
        "gmail.com", "googlemail.com", "yahoo.com", "ymail.com", "rocketmail.com",
        "outlook.com", "hotmail.com", "live.com", "msn.com", "hotmail.co.uk",
        "hotmail.fr", "live.fr", "outlook.fr", "windowslive.com",
        "icloud.com", "me.com", "mac.com", "aol.com", "aim.com",
        "protonmail.com", "proton.me", "pm.me", "tutanota.com", "tuta.io",
        "gmx.com", "gmx.net", "gmx.de", "gmx.fr", "mail.com", "email.com",
        "zoho.com", "zohomail.com", "yandex.com", "yandex.ru", "ya.ru",
        "fastmail.com", "hey.com", "hushmail.com", "inbox.com",
        "qq.com", "163.com", "126.com", "sina.com", "foxmail.com",
        "naver.com", "daum.net", "hanmail.net", "mail.ru", "list.ru", "bk.ru",
        // France (ISP / telco webmail)
        "orange.fr", "wanadoo.fr", "free.fr", "sfr.fr", "neuf.fr", "laposte.net",
        "bbox.fr", "numericable.fr", "aliceadsl.fr", "club-internet.fr", "voila.fr",
        // Germany
        "t-online.de", "web.de", "freenet.de", "arcor.de",
        // UK / Ireland
        "btinternet.com", "sky.com", "virginmedia.com", "talktalk.net",
        "ntlworld.com", "blueyonder.co.uk", "eircom.net",
        // US ISPs
        "comcast.net", "verizon.net", "att.net", "sbcglobal.net", "bellsouth.net",
        "cox.net", "charter.net", "earthlink.net", "roadrunner.com",
        // Canada
        "shaw.ca", "rogers.com", "telus.net", "sympatico.ca", "videotron.ca", "bell.net",
        // Italy / Spain / Portugal
        "libero.it", "virgilio.it", "alice.it", "tin.it", "tiscali.it",
        "terra.com", "telefonica.net", "sapo.pt",
        // Netherlands / Belgium / Nordics
        "ziggo.nl", "kpnmail.nl", "telenet.be", "skynet.be",
        "telia.com", "online.no",
        // Brazil / LatAm / India / Oceania
        "uol.com.br", "bol.com.br", "terra.com.br", "rediffmail.com",
        "bigpond.com", "optusnet.com.au"
    ]

    static func isFreeWebmail(_ domain: String) -> Bool {
        freeWebmail.contains(domain.lowercased())
    }
}
