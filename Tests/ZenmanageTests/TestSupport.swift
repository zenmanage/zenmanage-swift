import Foundation
import XCTest
@testable import Zenmanage

final class URLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var requestObserver: ((URLRequest) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            XCTFail("URLProtocolMock.requestHandler was not configured")
            return
        }

        do {
            Self.requestObserver?(request)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func makeURLSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolMock.self]
    return URLSession(configuration: configuration)
}

func makeConfiguration(
    environmentToken: String = "mob_test_key",
    cache: any RuleCache = InMemoryRuleCache(),
  enableUsageReporting: Bool = false,
    apiEndpoint: URL = URL(string: "https://api.zenmanage.com")!,
    urlSession: URLSession = makeURLSession()
) throws -> ZenmanageConfiguration {
    try ZenmanageConfiguration(
        environmentToken: environmentToken,
        cacheTTL: 3600,
        cache: cache,
        enableUsageReporting: enableUsageReporting,
        apiEndpoint: apiEndpoint,
        urlSession: urlSession
    )
}

func makeRulesResponseJSON() -> Data {
    let json = """
    {
      "version": "1",
      "flags": [
        {
          "version": "1",
          "type": "boolean",
          "key": "new-ui",
          "name": "New UI",
          "target": {
            "version": "1",
            "value": {
              "version": "1",
              "value": {
                "boolean": false
              }
            }
          },
          "rules": [
            {
              "clauses": [
                {
                  "attribute": "country",
                  "operator": "equal",
                  "value": "US"
                }
              ],
              "value": {
                "version": "1",
                "value": {
                  "boolean": true
                }
              }
            }
          ]
        },
        {
          "version": "2",
          "type": "string",
          "key": "checkout-flow",
          "name": "Checkout Flow",
          "target": {
            "version": "2",
            "value": {
              "version": "2",
              "value": {
                "string": "control"
              }
            }
          },
          "rollout": {
            "target": {
              "version": "2",
              "value": {
                "version": "2",
                "value": {
                  "string": "one-page"
                }
              }
            },
            "rules": [
              {
                "clauses": [
                  {
                    "attribute": "country",
                    "operator": "equal",
                    "value": "US"
                  }
                ],
                "value": {
                  "version": "2",
                  "value": {
                    "string": "one-page-us"
                  }
                }
              }
            ],
            "percentage": 100,
            "salt": "test-rollout-salt",
            "status": "active"
          }
        }
      ]
    }
    """

    return Data(json.utf8)
}

/// A rules payload that mirrors `makeRulesResponseJSON()` but also includes a flag with
/// an unrecognized `"json"` type and a value wrapper the SDK doesn't understand yet
/// (`{"json": ...}`), simulating what the API will send once json flags exist. Used to
/// verify an unrecognized flag degrades safely instead of throwing away the payload.
func makeRulesResponseJSONWithUnknownFlag() -> Data {
    let json = """
    {
      "version": "1",
      "flags": [
        {
          "version": "1",
          "type": "boolean",
          "key": "new-ui",
          "name": "New UI",
          "target": {
            "version": "1",
            "value": {
              "version": "1",
              "value": {
                "boolean": true
              }
            }
          }
        },
        {
          "version": "2",
          "type": "string",
          "key": "checkout-flow",
          "name": "Checkout Flow",
          "target": {
            "version": "2",
            "value": {
              "version": "2",
              "value": {
                "string": "control"
              }
            }
          }
        },
        {
          "version": "3",
          "type": "number",
          "key": "max-items",
          "name": "Max Items",
          "target": {
            "version": "3",
            "value": {
              "version": "3",
              "value": {
                "number": 10
              }
            }
          }
        },
        {
          "version": "4",
          "type": "json",
          "key": "advanced-config",
          "name": "Advanced Config",
          "target": {
            "version": "4",
            "value": {
              "version": "4",
              "value": {
                "json": {
                  "retries": 3,
                  "endpoints": ["a", "b"]
                }
              }
            }
          }
        }
      ]
    }
    """

    return Data(json.utf8)
}

func makeMetadataResponseJSON() -> Data {
    let json = """
    {
      "data": {
        "cdn": "https://cdn.example.com",
        "path": "/rules.json"
      }
    }
    """

    return Data(json.utf8)
}

func makeHTTPResponse(url: URL, statusCode: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}