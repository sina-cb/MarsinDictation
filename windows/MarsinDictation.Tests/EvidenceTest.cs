using System.Runtime.CompilerServices;
using Xunit.Abstractions;

namespace MarsinDictation.Tests;

/// <summary>
/// Base class for self-documenting tests.
/// Every test prints:
///   1. INTENT:  what is being tested in human language
///   2. EXPECT:  what evidence we look for
///   3. GOT:     what we actually observed
///   4. PASS/FAIL: verdict
///
/// Derive from this class to get structured, human-readable test output.
/// </summary>
public abstract class EvidenceTest
{
    protected readonly ITestOutputHelper Out;

    protected EvidenceTest(ITestOutputHelper output)
    {
        Out = output;
    }

    /// <summary>Describe the starting state or preconditions for this test.</summary>
    protected void Setup(string description)
    {
        Out.WriteLine($"  ┌ SETUP:  {description}");
    }

    /// <summary>State what this test is verifying in plain English.</summary>
    protected void Intent(string description)
    {
        Out.WriteLine($"  │ INTENT: {description}");
    }

    /// <summary>State what evidence we expect to see.</summary>
    protected void Expect(string evidence)
    {
        Out.WriteLine($"  │ EXPECT: {evidence}");
    }

    /// <summary>Record an observed value.</summary>
    protected void Got(string label, object? actual)
    {
        Out.WriteLine($"  │ GOT:    {label} = {actual}");
    }

    /// <summary>Record a passing check with explanation.</summary>
    protected void Pass(string reason)
    {
        Out.WriteLine($"  └ ✔ PASS: {reason}");
    }

    /// <summary>
    /// Assert equality with evidence logging.
    /// Logs the expected vs actual values, then asserts.
    /// </summary>
    protected void AssertEvidence<T>(string label, T expected, T actual)
    {
        Got(label, actual);
        if (!Equals(expected, actual))
        {
            Out.WriteLine($"  └ ✗ FAIL: {label} — expected [{expected}], got [{actual}]");
        }
        Xunit.Assert.Equal(expected, actual);
    }

    /// <summary>
    /// Assert a boolean condition with evidence logging.
    /// </summary>
    protected void AssertEvidence(string label, bool condition)
    {
        Got(label, condition);
        if (!condition)
        {
            Out.WriteLine($"  └ ✗ FAIL: {label} — expected true, got false");
        }
        Xunit.Assert.True(condition);
    }
}
