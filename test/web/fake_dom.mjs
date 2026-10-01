// A document that makes plain objects in place of DOM nodes, so that the views of the report page render in Node
// without a browser and without a package. It holds only what the views use.

export class FakeElement {
  constructor(tagName) {
    this.tagName = tagName.toLowerCase();
    this.attributes = new Map();
    this.children = [];
    this.parent = null;
    this.ownText = null;
    this.listeners = new Map();
  }

  setAttribute(name, value) {
    this.attributes.set(name, String(value));
  }

  getAttribute(name) {
    return this.attributes.get(name) ?? null;
  }

  appendChild(child) {
    child.parent = this;
    this.children.push(child);
    return child;
  }

  replaceChildren(...children) {
    this.children = [];
    this.ownText = null;
    for (const child of children) this.appendChild(child);
  }

  set textContent(text) {
    this.children = [];
    this.ownText = String(text);
  }

  get textContent() {
    return (
      this.ownText ?? this.children.map((child) => child.textContent).join("")
    );
  }

  addEventListener(type, listener) {
    this.listeners.set(type, [...(this.listeners.get(type) ?? []), listener]);
  }

  /** Calls the listeners of `type`, as a browser does for an event. */
  dispatch(type) {
    for (const listener of this.listeners.get(type) ?? [])
      listener({ type, target: this });
  }

  /** Every element under this one, this one first, in document order. */
  *descendants() {
    yield this;
    for (const child of this.children) yield* child.descendants();
  }

  /** Every element under this one with the tag `tagName`. */
  all(tagName) {
    return [...this.descendants()].filter(
      (element) => element.tagName === tagName,
    );
  }

  /** Every element under this one that has the class `className`. */
  withClass(className) {
    return [...this.descendants()].filter((element) =>
      (element.getAttribute("class") ?? "").split(" ").includes(className),
    );
  }

  /** The texts of the elements that hold text, in document order. */
  texts() {
    return [...this.descendants()]
      .filter((element) => element.ownText !== null)
      .map((element) => element.ownText);
  }
}

export class FakeDocument {
  constructor() {
    this.title = "";
  }

  createElement(tagName) {
    return new FakeElement(tagName);
  }
}
