VS Code 左侧 Explorer 里**单击文件**时，是否复用当前 Tab，核心取决于 **Preview Mode（预览模式）**。可以简单理解成：

| **操作**                       | **默认行为**                                        |
| ------------------------------ | --------------------------------------------------- |
| 单击文件                       | 以 **Preview Tab** 打开，通常会替换当前 Preview Tab |
| 双击文件                       | 正式打开一个 Tab，不会被后续单击替换                |
| 单击一个已经打开的 Preview Tab | 切换到它                                            |
| 编辑 Preview Tab 内容          | 通常会把它“固定”为普通 Tab                          |
| `Ctrl+P` 后回车打开文件        | 默认也是 Preview 方式                               |
| `Ctrl+P` 后 `Ctrl+Enter`       | 强制以普通 Tab 打开                                 |

### **1. 什么是 Preview Tab？**

比如你现在：

```text
Explorer
├── a.ts
├── b.ts
├── c.ts
```

当前正在看 `a.ts`。

你**单击** `b.ts`：

```text
[a.ts]  →  [b.ts]
```

此时 `b.ts` 是一个 **Preview Tab**，一般 Tab 标题会用**斜体**显示。

接着你再单击 `c.ts`：

```text
[b.ts]  →  [c.ts]
```

而不是：

```text
[a.ts] [b.ts] [c.ts]
```

也就是说，VS Code 默认认为：

“用户只是想快速瞄一眼这个文件。”

所以它不会不断制造 Tab。

------

### **2. 什么情况下会新建一个正式 Tab？**

最常见的是**双击文件**：

```text
双击 a.ts
```

变成：

```text
[a.ts]
```

这个 Tab 就是普通 Tab（pinned / non-preview），之后你再单击其他文件：

```text
[a.ts] [b.ts]
```

`b.ts` 可以成为 Preview Tab，而 `a.ts` 不会被替换。

所以你可以把它理解成：

- **单击 = “让我看看”**
- **双击 = “我要一直开着它”**

------

### **3. 为什么有时候单击也会新建 Tab？**

这里容易产生误解，因为 **Preview Tab 是“一个槽位”**，不是说 VS Code 永远只允许一个 Tab。

例如你已经有：

```text
[a.ts] [b.ts]
```

其中 `a.ts`、`b.ts` 都是普通 Tab。

现在单击 `c.ts`：

```text
[a.ts] [b.ts] [c.ts]
```

`c.ts` 是 Preview Tab。

然后单击 `d.ts`：

```text
[a.ts] [b.ts] [d.ts]
```

这里被替换的是 **Preview Tab** **`c.ts`**，而不是 `a.ts` 或 `b.ts`。

所以更准确地说：

**单击文件时，VS Code 会优先复用当前编辑器组中的 Preview Tab；如果没有 Preview Tab，就创建一个新的 Preview Tab。**

------

### **4. 还有一个容易忽略的情况：Preview Tab 被“固定”了**

假设：

```text
[a.ts] [b.ts]
```

`b.ts` 是 Preview。

如果你开始修改 `b.ts`，或者执行某些会使它变成普通 Tab 的操作，它可能就不再是 Preview。

这时候再单击 `c.ts`：

```text
[a.ts] [b.ts] [c.ts]
```

而不会把 `b.ts` 换掉。

### **一句话总结**

VS Code 默认的 Tab 策略其实就是：

**单击 = Preview，可复用；双击 = 正式 Tab，不复用。**

因此你看到的“**点击一个文件把当前 Tab 替换掉**”，本质上不是 VS Code 在关闭/覆盖一个普通 Tab，而是**连续的单击操作在复用同一个 Preview Tab**。