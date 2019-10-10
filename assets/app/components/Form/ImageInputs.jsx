import React, { Component } from "react";
import classNames from "classnames";
import ImageInput from "./ImageInput.jsx";

class ImageInputs extends Component {
  constructor(props) {
    super(props);

    this.handleClickAddImage = this.handleClickAddImage.bind(this);
  };

  handleClickAddImage(event) {
    event.preventDefault();

    this.props.onClickAddImage();
  }

  render() {
    const imageInputs = this.props.imageFiles.map((imageFile, index) => {
      const updateImage = (file) => {
        this.props.onChangeImage(index, file);
      };

      const removeImage = () => {
        this.props.onClickRemoveImage(index);
      };

      return (<ImageInput key={imageFile.id} file={imageFile} onChangeImage={updateImage} onClickRemoveImage={removeImage} disabled={this.props.disabled}/>);
    });

    const className = classNames({
      "image-inputs": true,
      "hide": this.props.disabled
    });

    return (
      <div className={className}>
        {imageInputs}
        <div className="row">
          <div className="col s12">
            <button className="add-image-button waves-effect waves-light btn" onClick={this.handleClickAddImage}>Add Image</button>
          </div>
        </div>
      </div>
    );
  }
}

export default ImageInputs;
