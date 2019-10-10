import React, { Component } from "react";
import classNames from "classnames";

class ArchiveInput extends Component {
  render() {
    const className = classNames({
      "archive-input": true,
      "row": true,
      "hide": this.props.disabled
    });

    let selectedText;

    if (this.props.archiveFile && this.props.archiveFile.name) {
      selectedText = `Selected file: ${this.props.archiveFile.name}`;
    }

    return (
      <div className={className}>
        <label className="col s3">
          <span className="archive-input-label waves-effect waves-light btn">Select File</span>
          <input name="archive_file" type="file" style={{ display: "none" }} disabled={this.props.disabled}/>
        </label>
        <div className="archive-file-name col s3">
          {selectedText}
        </div>
      </div>
    );
  }
}

export default ArchiveInput;
