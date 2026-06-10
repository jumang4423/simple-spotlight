import Testing
@testable import SimpleSpotlight

@Suite
struct CalculatorTests {
    private let calculator = Calculator()

    @Test
    func arithmeticExpression() {
        #expect(calculator.evaluate("500 / 2 * 250") == 62500)
    }

    @Test
    func scientificExpression() {
        #expect(calculator.evaluate("sqrt(9)") == 3)
        #expect(abs((calculator.evaluate("sin(pi / 2)") ?? 0) - 1) < 0.000001)
        #expect(calculator.evaluate("2^8") == 256)
    }

    @Test
    func invalidExpressionReturnsNil() {
        #expect(calculator.evaluate("hello") == nil)
        #expect(calculator.evaluate("1 / 0") == nil)
        #expect(calculator.evaluate("sqrt(-1)") == nil)
    }
}
