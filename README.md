# StateMachine with demo application

## Background (Why did I create this project?)

Many years ago I worked as software engineer at various companies in the Greater Seattle area including Traveling Software in Bothell, WA. I was a systems programmer who had gotten his start on the MOS Technology 6502/6510 using Commodore computer systems like the PET. I later graduated to DOS running on the 8088 processor, and specialized in computer-to-computer communication. As a designer and implementer of computer communication protocols, I existed inclusively between layer five and layer two in the ISO/OSI Model. Most of my code was written in x86 Assembly Language, and later on, in C. I wrote code at the operating system level for things like memory/resource management, task scheduling, device-drivers, and protocol stack implementation.

At one point, I went to work for Traveling Software,the creators of LapLink™. The Laplink app allowed users to perform file transfers and run remote-control sessions between two PC computers running Windows 95™, ideally one of them being a laptop computer. Physical connections between the computers were established the standard IBM-PC serial-port, parallel-port or, alternatively, the IPX LAN networking protocol.

During my tenure at TS, I became responsible for implementing the serial-port and parallel-port protocols, as well as writing the hardware support for the new Windows version of this product (Previously a DOS-only implementation was available but that was before my time, for the most part.)

As a team, I and three others, designed a new proprietry protocol stack modeled after OSI. It covered everything from the hardware interfaces all the way up to the *Session* layer. In order to implement my portion of the stack, I came up with a low-level Finite State Machine implementation that relied on the principles of a traditional flat table-driven approach combined with the principles of what was then known as `Harel State-Chart`s. David Harel's approach included things like entry and exit actions, do activity, nesting, conditional event evaluations and so on. If you are familiar with the more modern-day UML-State diagrams, then you know what I'm talking about.

For my implementation, I needed an FSM implementation that was thread-safe and could easily be specified, configured and re-configured, audited at run-time for correctness, and did not rely on dynamic memory allocation since virtual DOS mode was a thing in Windows 95. There were other constraints but the memory is fading. In any case, I decided to re-create my state machine implementation as a possible component for a personal communications project I'm building for the iPad but in Swift and using Swift Concurrency, where appropriate. I wanted my solution to be compatible with Swift 6 and strict concurrency. This project is the result of my research thus far.

I decided to use AI to generate the code instead of writing it myself. I use AI the way a micro-managing lead software engineer uses a junior sofware engineer. Ultimately, I don't trust it and check every output and require it to ask permission for anything that requires using *git* or leaving the shared working directory.

One of the best techniques I've found for my AI workflow is making the AI document everything as we go in a *Markdown* document consisting of text, *Mermaid* diagrams and code snippets; sort of like planning mode but with a written record. This allows me to review progress, decisions that were jointly reasoned about and then implemented, and to explore alternatives up front. If, in the process of experimenting, I discover that we've gone down a dead-end or made a bad design or implementation choice, instead of re-writing the document, we append a new section so that the history is preserved. I don't know if this is a common technique but it certainly works well for me. In the document I make sure that there are plenty of charts and diagrams; object/actor model diagrams, state-chart diagrams, sequence diagrams, etc. The ideas is that I want a fellow team member or associate to be able to immediately understand the underlying design and shape of the sofware, so as to pick-up exactly where I left off, in case I get hit by the proverbial truck.

In this project, that record may be found in [StateMachineContext.md](./StateMachineContext.md).

## Documentation

See [StateMachineContext.md](./StateMachineContext.md)
