import Foundation
import Testing
@testable import Ghostty

// The focused session's repo sorts first, so the sorter needs "org/repo" from
// whatever `git remote get-url origin` returns. Every remote spelling GitHub
// uses must parse; anything else returns nil rather than a wrong slug.
struct HolyInboxRepoSlugTests {
    @Test func parsesSSHColonForm() {
        #expect(
            HolyGitHubRemoteParser.slug(fromRemoteURL: "git@github.com:ovachiever/holy-ghostty.git")
                == "ovachiever/holy-ghostty"
        )
    }

    @Test func parsesHTTPSFormWithAndWithoutDotGit() {
        #expect(
            HolyGitHubRemoteParser.slug(fromRemoteURL: "https://github.com/org/repo.git")
                == "org/repo"
        )
        #expect(
            HolyGitHubRemoteParser.slug(fromRemoteURL: "https://github.com/org/repo")
                == "org/repo"
        )
    }

    @Test func parsesSSHURLForm() {
        #expect(
            HolyGitHubRemoteParser.slug(fromRemoteURL: "ssh://git@github.com/org/repo.git")
                == "org/repo"
        )
    }

    @Test func trimsWhitespaceAndTrailingSlash() {
        #expect(
            HolyGitHubRemoteParser.slug(fromRemoteURL: "  https://github.com/org/repo/  \n")
                == "org/repo"
        )
    }

    @Test func rejectsShapesWithoutTwoPathComponents() {
        #expect(HolyGitHubRemoteParser.slug(fromRemoteURL: "") == nil)
        #expect(HolyGitHubRemoteParser.slug(fromRemoteURL: "https://github.com/") == nil)
        #expect(HolyGitHubRemoteParser.slug(fromRemoteURL: "not a url") == nil)
    }
}
