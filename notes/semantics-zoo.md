# The effect semantics zoo

Not all effect systems implement the same semantics, particularly when so-called “scoping operators” are involved. This document collects examples that serve as useful “acid tests” for distinguishing a given effect system’s semantics.

Code examples are given using an `eff`-style API. Unless otherwise noted, these can be mechanically translated to the APIs of other libraries, so only the results are listed.

## `State` + `Error`

This is the classic example of differing behavior under effect reordering. Here is our test program:

```haskell
action :: (State Bool :< es, Error () :< es) => Eff es Bool
action = do
  (put True *> throw ()) `catch` \() -> pure ()
  get

main :: IO ()
main = do
  print $ run (evalState False $ runError @() action)
  print $ run (runError @() $ evalState False action)
```

Here are the results:

<table>
  <thead>
    <tr>
      <th align="center">Implementation</th>
      <th align="center"><code>Error</code> inner</th>
      <th align="center"><code>State</code> inner</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>mtl</code></td>
      <td rowspan="4"><code>Right True</code></td>
      <td rowspan="3"><code>Right False</code></td>
    </tr>
    <tr><td><code>fused-effects</code></td></tr>
    <tr><td><code>polysemy</code></td></tr>
    <tr>
      <td><code>eff</code></td>
      <td><code>Right True</code></td>
    </tr>
  </tbody>
</table>

### Discussion

All implementations agree when the `Error` handler is inside the `State` handler, but `eff` disagrees with the other implementations when the reverse is true. When the `State` handler is innermost, `mtl`-family libraries provide so-called “transactional state semantics”, which results in modifications to the state within the scope of a `catch` being discarded if an exception is raised.

The transactional semantics is sometimes useful, so this is sometimes provided as an example of why the `mtl`-family semantics is a feature, not a bug. However, it is really just a specific instance of a more general class of interactions that cause `mtl`-family libraries discard state, and other instances are more difficult to justify. For that reason, my perspective is that this behavior constitutes a bug, and `eff` breaks rank accordingly.

## `NonDet` + `Error`

Let’s modify the previous test program to use `NonDet` instead of `State`:

```haskell
action1, action2 :: (NonDet :< es, Error () :< es) => Eff es Bool
action1 = (pure True <|> throw ()) `catch` \() -> pure False
action2 = (throw () <|> pure True) `catch` \() -> pure False

main :: IO ()
main = do
  print $ run (runNonDetAll @[] $ runError @() action1)
  print $ run (runError @() $ runNonDetAll @[] action1)
  print $ run (runNonDetAll @[] $ runError @() action2)
  print $ run (runError @() $ runNonDetAll @[] action2)
```

And the results:

<table>
  <thead>
    <tr>
      <th align="center">Implementation</th>
      <th align="center"><code>action1</code>, <code>Error</code> inner</th>
      <th align="center"><code>action1</code>, <code>NonDet</code> inner</th>
      <th align="center"><code>action2</code>, <code>Error</code> inner</th>
      <th align="center"><code>action2</code>, <code>NonDet</code> inner</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>mtl</code> + <code>list-t</code></td>
      <td rowspan="2"><code>[Right True]</code></td>
      <td><code>Left ()</code></td>
      <td rowspan="2"><code>[Right True]</code></td>
      <td rowspan="4"><code>Right [False]</code></td>
    </tr>
    <tr>
      <td><code>mtl</code> + <code>pipes</code></td>
      <td><code>Right [True, False]</code></td>
    </tr>
    <tr>
      <td><code>fused-effects</code></td>
      <td rowspan="3"><code>[Right True, Right False]</code></td>
      <td rowspan="2"><code>Right [False]</code></td>
      <td rowspan="3"><code>[Right False, Right True]</code></td>
    </tr>
    <tr>
      <td><code>polysemy</code></td>
    </tr>
    <tr>
      <td><code>eff</code></td>
      <td><code>Right [True, False]</code></td>
      <td><code>Right [False, True]</code></td>
    </tr>
  </tbody>
</table>

### Discussion

The results in this case are much more interesting, as there is significantly more disagreement! Let’s go over the different libraries one by one:

  * In the case of `list-t`, I think its `MonadError` instance is unfortunately just plain broken, as it makes no attempt to install the `catch` handler on branch of execution other than the first. For that reason, I think its behavior can be mostly disregarded.

  * `pipes` does somewhat better, getting at least the “`action1`, `NonDet` inner” case right, but the behavior when the `Error` handler is innermost is frankly mystifying to me. I haven’t investigated what exactly causes that.

  * `fused-effects` and `polysemy` agree on all counts. This is closest to the behavior I would expect from the `mtl`-family libraries, so I consider the `list-t` and `pipes` behavior somewhat anomalous.

  * `eff` agrees with `fused-effects` and `polysemy` in cases where the `Error` handler is innermost, but it disagrees when `NonDet` is innermost. This mirrors its disagreement on the `State` + `Error` test above.

Such extreme disagreement naturally leads us to ask: who is right? Unfortunately, without any well-defined laws or underlying semantics, there is no definitive answer. Barring that, the best we can do is appeal to our intuitions.

As the author of `eff`, it is probably unsurprising that I believe `eff`’s behavior is the right one. However, whether you agree or disagree with me, I can at least outline my reasoning:

  * For starters, I think we can immediately throw out `list-t`’s answer on the “`action1`, `NonDet` inner” case. There is absolutely no way to justify any of these results being `Left`, as the only `throw` always appears inside a `catch`.

  * Similarly, I think we can throw out the `list-t` and `pipes` answers for the “`Error` inner” cases. In those cases, the throw exceptions *are* caught, as evidenced by no `Left` results appearing in the output, but there’s no `Right` result, either—the branch of execution seems to “vanish into thin air”, like a ship mysteriously lost in the Bermuda triangle.

    If you accept that argument, the remaining libraries—`fused-effects`, `polysemy`, and `eff`—all agree on those cases, producing the answer I think one would intuitively expect.

  * This leaves only the “`NonDet` inner” cases. `fused-effects` and `polysemy`  produce `Right [False]` in both cases, while `eff` produces `Right [True, False]` and `Right [False, True]`, respectively.

    I think the `Right [False]` answer is hard to justify in the case of `action1`, where the exception is only raised in the second branch of execution. What happened to the first branch? It seems as though it’s vanished into the Bermuda triangle, too.

    Interestingly, `pipes` agrees with `eff` in the case of `action1`, but it disagrees in the case of `action2`. I think this actually makes dramatically more sense than the `fused-effects` and `polysemy` behavior: it suggests a `throw` discards all *local* branches up to the nearest enclosing `catch`, mirroring the transactional state semantics described above.

    `eff` is, in contrast, unwaveringly consistent: it always adheres to its continuation-based semantics, so `<|>` always forks the computation up to its handler, which duplicates the `catch` frame regardless of handler order, resulting in consistent results and no discarding of state.

To summarize, I think there are really only two justifiable semantics here:

<table>
  <thead>
    <tr>
      <th align="center">Semantics</th>
      <th align="center"><code>action1</code>, <code>Error</code> inner</th>
      <th align="center"><code>action1</code>, <code>NonDet</code> inner</th>
      <th align="center"><code>action2</code>, <code>Error</code> inner</th>
      <th align="center"><code>action2</code>, <code>NonDet</code> inner</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>local</td>
      <td rowspan="2"><code>[Right True, Right False]</code></td>
      <td rowspan="2"><code>Right [True, False]</code></td>
      <td rowspan="2"><code>[Right False, Right True]</code></td>
      <td><code>Right [False]</code></td>
    </tr>
    <tr>
      <td>global</td>
      <td><code>Right [False, True]</code></td>
    </tr>
  </tbody>
</table>

`eff`’s continuation-based semantics is consistent with the “global” row, but *none* of the libraries tested are consistent with the “local” row. I think this makes it difficult to argue that any of them are correct: I consider all libraries but `eff` broken on this example.

## `NonDet` + `Writer`

`catch` is usually the go-to example of a scoping operator, but the `Writer` effect also includes one in the form of `listen`. Here’s a test case that exercises `listen` in combination with `NonDet`:

```haskell
action :: (NonDet :< es, Writer (Sum Int) :< es) => Eff es ((Sum Int), Bool)
action = listen (add 1 *> (add 2 $> True <|> add 3 $> False))
  where add = tell . Sum @Int

main :: IO ()
main = do
  print $ run (runNonDetAll @[] $ runWriter @(Sum Int) action)
  print $ run (runWriter @(Sum Int) $ runNonDetAll @[] action)
```

Here are the results (omitting the wrapping `Sum` constructors in the output for the sake of brevity and clarity):

<table>
  <thead>
    <tr>
      <th align="center">Implementation</th>
      <th align="center"><code>Writer</code> inner</th>
      <th align="center"><code>NonDet</code> inner</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>mtl</code> + <code>list-t</code></td>
      <td rowspan="5"><code>[(3, (3, True)), (4, (4, False))]</code></td>
      <td align="center">N/A — no <code>MonadWriter</code> instance</td>
    </tr>
    <tr>
      <td><code>mtl</code> + <code>pipes</code></td>
      <td><code>(6, [(3, True), (6, False)])</code></td>
    </tr>
    <tr>
      <td><code>fused-effects</code></td>
      <td rowspan="2"><code>(6, [(6, True), (6, False)])</code></td>
    </tr>
    <tr><td><code>polysemy</code></td></tr>
    <tr>
      <td><code>eff</code></td>
      <td><code>(6, [(3, True), (4, False)])</code></td>
    </tr>
  </tbody>
</table>

### Discussion

The results of the `NonDet` + `Writer` test are less shocking than they were for `NonDet` + `Error`, but there is still significant disagreement when the `NonDet` handler is innermost. Fortunately, when the `Writer` handler is innermost, there is no disagreement, as in the `State` + `Error` test.

Let’s start this time by considering `eff`’s semantics. As always, `eff` adheres to a continuation-based model, where `<|>` forks the continuation delimited by the `NonDet` handler. In this case, that duplicates the `listen` frame, which means `listen` distributes over `<|>` once the `<|>` becomes the redex. Working through the reduction using those rules neatly explains both of its results.

`pipes`, `fused-effects`, and `polysemy` disagree with this semantics. The answer given by `fused-effects` and `polysemy` makes some sense: we can interpret `listen` in the “`NonDet` inner” scenario as being “transactional” in that it observes `tell` output from all computational branches within its scope. It does, however, make the meaning of `NonDet` somewhat less intuitive, as if you interpret `NonDet` as a way of “splitting the world” nondeterministically, `listen` must somehow implicitly span across *all* worlds, despite knowing nothing about `NonDet`.

The behavior of `pipes` is even more unusual, as `listen` still spans across multiple worlds, but each branch only sees the state accumulated from the current world and previous ones. This means `listen` also observes the *order* in which the worlds are executed, so changing the order in which branches are taken could result in meaningfully different results.

All three interpretations of `listen` are interesting, and one can imagine situations in which all of them might be useful. However, it’s worth contemplating which behavior is most intuitive to offer *by default*, as well as what the programmer would have to do to obtain a behavior other than the default one. In `eff`, the answer is fairly simple: to allow `listen` to span multiple worlds, its handler must somehow be in cahoots with the `NonDet` handler, and otherwise it should be oblivious to the `NonDet` handler’s presence. In the other systems, it’s less clear how to recover `eff`’s behavior other than to replace `listen` with the local introduction of a separate `runWriter` handler that explicitly relays to the enclosing one.
